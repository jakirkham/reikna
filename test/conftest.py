from itertools import product

import numpy

import tigger.cluda as cluda


pytest_plugins = ['pytest_returnvalues']


def pytest_addoption(parser):
    parser.addoption("--api", action="store",
        help="API: cuda/ocl/supported",
        default="supported", choices=["cuda", "ocl", "supported"])
    parser.addoption("--double", action="store",
        help="Use doubles: no/yes/supported",
        default="supported", choices=["no", "yes", "supported"])
    parser.addoption("--fast-math", dest="fast_math", action="store",
        help="Use fast math: no/yes/both",
        default="yes", choices=["no", "yes", "both"])

def pytest_funcarg__ctx_and_double(request):
    """
    Create context before call to test and release it when the test ends
    """
    cc, dv = request.param
    ctx = cc()
    request.addfinalizer(lambda: ctx.release())
    return ctx, dv

def pytest_funcarg__ctx(request):
    """
    Create context before call to test and release it when the test ends
    """
    cc = request.param
    ctx = cc()
    request.addfinalizer(lambda: ctx.release())
    return ctx

def get_contexts(metafunc):
    """
    Create a list of context creators and corresponding ids to parameterize tests
    """

    def check_api(name):
        return dict(cuda=cluda.supportsCuda, ocl=cluda.supportsOcl)[name]()

    class CtxCreator:
        def __init__(self, api, fast_math):
            self.fast_math = fast_math
            self.api = api
            ctr = dict(cuda=cluda.createCuda, ocl=cluda.createOcl)[api]
            self.create = lambda: ctr(fast_math=fm)

        def __call__(self):
            return self.create()

        def __str__(self):
            return self.api + (",fm" if self.fast_math else "")

    api = metafunc.config.option.api
    fm = metafunc.config.option.fast_math

    if api == "supported":
        apis = []
        for name in ('cuda', 'ocl'):
            if check_api(name): apis.append(name)
    else:
        if not check_api(api):
            raise Exception("Requested API " + api + " is not supported.")
        apis = [api]

    if fm == "both":
        fms = [False, True]
    elif fm == "no":
        fms = [False]
    else:
        fms = [True]

    ccs = [CtxCreator(api, fm) for api, fm in product(apis, fms)]
    return ccs, [str(cc) for cc in ccs]

def get_contexts_and_doubles(metafunc, ccs, cc_ids):
    """
    Create a list of (context creator, use-double) pairs
    and corresponding ids to parameterize tests.
    """
    d = metafunc.config.option.double
    ds = lambda dv: 'dp' if dv else 'sp'

    vals = []
    ids = []
    if d == "supported":
        for cc_and_id, dv in product(zip(ccs, cc_ids), [False, True]):
            cc, cc_id = cc_and_id
            if not dv or cc().supportsDtype(numpy.float64):
                vals.append((cc, dv))
                ids.append(cc_id + "," + ds(dv))
    else:
        dv = d == 'yes'
        for cc, cc_id in zip(ccs, cc_ids):
            vals.append((cc, dv))
            ids.append(cc_id + "," + ds(dv))

    return vals, ids

def pytest_generate_tests(metafunc):

    if 'ctx_and_double' in metafunc.funcargnames:
        ccs, cc_ids = get_contexts(metafunc)
        ccs_and_doubles, ids = get_contexts_and_doubles(metafunc, ccs, cc_ids)
        metafunc.parametrize('ctx_and_double', ccs_and_doubles, ids=ids, indirect=True)

    if 'ctx' in metafunc.funcargnames:
        ccs, cc_ids = get_contexts(metafunc)
        metafunc.parametrize('ctx', ccs, ids=cc_ids, indirect=True)
