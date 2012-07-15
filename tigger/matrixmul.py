import numpy
import helpers
from tigger.core.helpers import AttrDict, template_for, min_blocks
from tigger.core.computation import *
from tigger.core.transformation import *

TEMPLATE = template_for(__file__)


class MatrixMul(Computation):

    def _get_default_basis(self):
        return AttrDict(a_dtype=numpy.float32, b_dtype=numpy.float32, out_dtype=numpy.float32,
            a_height=1, a_width=1, b_width=1, batch=1,
            batched_a=False, batched_b=False,
            block_size_override=None)

    def _construct_basis(self, out, a, b):

        bs = AttrDict()

        if self._debug:
            # TODO: this check should be made automatically somewhere in core.transformation
            for dtype in (a.dtype, b.dtype, out.dtype):
                assert self._env.supportsDtype(dtype)

        bs.out_dtype = out.dtype
        bs.a_dtype = a.dtype
        bs.b_dtype = b.dtype

        # Derive shapes

        if self._debug:
            assert len(a.shape) >= 2
            assert len(b.shape) >= 2
            assert a.shape[-1] == b.shape[-2]

        a_batch = product(a.shape[:-2])
        b_batch = product(b.shape[:-2])
        out_batch = max(a_batch, b_batch)

        if out is None or self._debug:
            out_shape = (b.shape[:-2] if a_batch == 1 else a.shape[:-2]) + (a.shape[-2], b.shape[-1])
        else:
            out_shape = out.shape

        if self._debug:
            assert a_batch == 1 or b_batch == 1 or a_batch == b_batch
            assert a_batch != b_batch or a.shape[:-2] == b.shape[:-2]
            if out is not None:
                assert len(out_shape) >= 2
                assert out_batch == product(out_shape[:-2])

        bs.update(dict(
            a_width=a.shape[-1],
            a_height=a.shape[-2],
            b_width=b.shape[-1],
            batch=out_batch,
            batched_a=(a_batch == 1),
            batched_b=(b_batch == 1),
            out_shape=out_shape))

        return bs

    def _get_base_signature(self):
        bs = self._basis
        return [('C', ArrayValue(None, bs.out_dtype))], \
            [
                ('A', ArrayValue(None, bs.a_dtype)),
                ('B', ArrayValue(None, bs.b_dtype))], \
            []

    def _construct_kernels(self):
        bs = self._basis

        bso = bs.block_size_override
        block_size = self._env.params.smem_banks if bso is None else bso

        blocks_per_matrix = min_blocks(bs.a_height, block_size)
        grid = (
            int(min_blocks(bs.b_width, block_size)),
            int(blocks_per_matrix * bs.batch)
        )
        block = (block_size, block_size, 1)
        shared = block_size * block_size * (bs.a_dtype.itemsize + bs.b_dtype.itemsize)

        src = self._render(TEMPLATE,
            block_size=block_size,
            blocks_per_matrix=blocks_per_matrix,
            )

        return [KernelCall(
            'matrixmul', ['C', 'A', 'B'], src,
            grid=grid, block=block, shared=shared
        )]


class MockMatrixMul(MatrixMul):

    def _dot(self, out, a, b):
        basis = db if self._dynamic else self._basis

        ha, wa, wb, batch, batched_a, batched_b, scale = \
            basis.a_height, basis.a_width, basis.b_width, \
            basis.batch, basis.batched_a, basis.batched_b, self._scale

        a_view = a.reshape(batch if batched_a else 1, ha, wa)
        b_view = b.reshape(batch if batched_b else 1, wa, wb)
        out_view = out.reshape(batch, ha, wb)

        for i in xrange(batch):
            a_part = a_view[i] if batched_a else a_view[0]
            b_part = b_view[i] if batched_b else b_view[0]
            out_view[i] = numpy.dot(a_part, b_part)

        out_view *= scale