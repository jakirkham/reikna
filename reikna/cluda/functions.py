from warnings import warn

import numpy

import reikna.helpers as helpers
from reikna.helpers import template_for
from reikna.cluda import dtypes
from reikna.cluda.kernel import Module


TEMPLATE = template_for(__file__)


def check_information_loss(out_dtype, expected_dtype):
    if dtypes.is_complex(expected_dtype) and not dtypes.is_complex(out_dtype):
        warn("Imaginary part ignored during the downcast from " +
            str(expected_dtype) + " to " + str(out_dtype),
            numpy.ComplexWarning)


def derive_out_dtype(out_dtype, *in_dtypes):
    expected_dtype = dtypes.result_type(*in_dtypes)
    if out_dtype is None:
        out_dtype = expected_dtype
    else:
        check_information_loss(out_dtype, expected_dtype)
    return out_dtype


def cast(out_dtype, in_dtype):
    """
    Returns a :py:class:`reikna.cluda.kernel.Module`
    that casts values of ``in_dtype`` to ``out_dtype``.
    """
    return Module(
        TEMPLATE.get_def('cast'),
        render_kwds=dict(out_dtype=out_dtype, in_dtype=in_dtype))


def mul(*in_dtypes, **kwds):
    """mul(*in_dtypes, out_dtype=None)

    Returns a :py:class:`reikna.cluda.kernel.Module`
    that multiplies values of types ``in_dtypes``.
    If ``out_dtype`` is given, it will be set as a return type for this function.
    """
    assert set(kwds.keys()).issubset(['out_dtype'])
    out_dtype = derive_out_dtype(kwds.get('out_dtype', None), *in_dtypes)
    return Module(
        TEMPLATE.get_def('mul'),
        render_kwds=dict(out_dtype=out_dtype, in_dtypes=in_dtypes))


def div(in_dtype1, in_dtype2, out_dtype=None):
    """
    Returns a :py:class:`reikna.cluda.kernel.Module`
    that divides values of ``in_dtype1`` and ``in_dtype2``.
    If ``out_dtype`` is given, it will be set as a return type for this function.
    """
    out_dtype = derive_out_dtype(out_dtype, in_dtype1, in_dtype2)
    return Module(
        TEMPLATE.get_def('div'),
        render_kwds=dict(out_dtype=out_dtype, in_dtype1=in_dtype1, in_dtype2=in_dtype2))


def conj(dtype):
    """
    Returns a :py:class:`reikna.cluda.kernel.Module`
    that conjugates the value of type ``dtype`` (must be a complex data type).
    """
    if not dtypes.is_complex(dtype):
        raise NotImplementedError("conj() of " + str(dtype) + " is not supported")

    return Module(
        TEMPLATE.get_def('conj'),
        render_kwds=dict(dtype=dtype))


def norm(dtype):
    """
    Returns a :py:class:`reikna.cluda.kernel.Module`
    that returns the norm of the value of type ``dtype``
    (product by the complex conjugate if the value is complex, square otherwise).
    """
    return Module(
        TEMPLATE.get_def('norm'),
        render_kwds=dict(dtype=dtype))


def exp(dtype):
    """
    Returns a :py:class:`reikna.cluda.kernel.Module`
    that exponentiates the value of type ``dtype``
    (must be a real or complex data type).
    """
    if dtypes.is_integer(dtype):
        raise NotImplementedError("exp() of " + str(dtype) + " is not supported")

    return Module(
        TEMPLATE.get_def('exp'),
        render_kwds=dict(dtype=dtype))


def polar(dtype):
    """
    Returns a :py:class:`reikna.cluda.kernel.Module`
    that calculates ``rho * exp(i * theta)``
    for values ``rho, theta`` of type ``dtype`` (must be a real data type).
    """
    if not dtypes.is_real(dtype):
        raise NotImplementedError("polar() of " + str(dtype) + " is not supported")

    return Module(
        TEMPLATE.get_def('polar'),
        render_kwds=dict(dtype=dtype))