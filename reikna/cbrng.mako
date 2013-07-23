<%def name="rng_threefry(rng_params)">
<%
    N = rng_params.words
    W = rng_params.bitness
    rounds = rng_params.rounds
    key = rng_params.key

    ctype = dtypes.ctype(numpy.uint32 if W == 32 else numpy.uint64)

    # Rotation constants:
    r123_enum_threefry = {
        # These are the R_256 constants from the Threefish reference sources
        # with names changed to R_64x4...
        (64, 4): numpy.array([[14, 52, 23, 5, 25, 46, 58, 32], [16, 57, 40, 37, 33, 12, 22, 32]]).T,

        # Output from skein_rot_search: (srs64_B64-X1000)
        # Random seed = 1. BlockSize = 128 bits. sampleCnt =  1024. rounds =  8, minHW_or=57
        # Start: Tue Mar  1 10:07:48 2011
        # rMin = 0.136. #0325[*15] [CRC=455A682F. hw_OR=64. cnt=16384. blkSize= 128].format
        (64, 2): numpy.array([[16, 42, 12, 31, 16, 32, 24, 21]]).T,
        # 4 rounds: minHW =  4  [  4  4  4  4 ]
        # 5 rounds: minHW =  8  [  8  8  8  8 ]
        # 6 rounds: minHW = 16  [ 16 16 16 16 ]
        # 7 rounds: minHW = 32  [ 32 32 32 32 ]
        # 8 rounds: minHW = 64  [ 64 64 64 64 ]
        # 9 rounds: minHW = 64  [ 64 64 64 64 ]
        # 10 rounds: minHW = 64  [ 64 64 64 64 ]
        # 11 rounds: minHW = 64  [ 64 64 64 64 ]

        # Output from skein_rot_search: (srs-B128-X5000.out)
        # Random seed = 1. BlockSize = 64 bits. sampleCnt =  1024. rounds =  8, minHW_or=28
        # Start: Mon Aug 24 22:41:36 2009
        # ...
        # rMin = 0.472. #0A4B[*33] [CRC=DD1ECE0F. hw_OR=31. cnt=16384. blkSize= 128].format
        (32, 4): numpy.array([[10, 11, 13, 23, 6, 17, 25, 18], [26, 21, 27, 5, 20, 11, 10, 20]]).T,
        # 4 rounds: minHW =  3  [  3  3  3  3 ]
        # 5 rounds: minHW =  7  [  7  7  7  7 ]
        # 6 rounds: minHW = 12  [ 13 12 13 12 ]
        # 7 rounds: minHW = 22  [ 22 23 22 23 ]
        # 8 rounds: minHW = 31  [ 31 31 31 31 ]
        # 9 rounds: minHW = 32  [ 32 32 32 32 ]
        # 10 rounds: minHW = 32  [ 32 32 32 32 ]
        # 11 rounds: minHW = 32  [ 32 32 32 32 ]

        # Output from skein_rot_search (srs32x2-X5000.out)
        # Random seed = 1. BlockSize = 64 bits. sampleCnt =  1024. rounds =  8, minHW_or=28
        # Start: Tue Jul 12 11:11:33 2011
        # rMin = 0.334. #0206[*07] [CRC=1D9765C0. hw_OR=32. cnt=16384. blkSize=  64].format
        (32, 2): numpy.array([[13, 15, 26, 6, 17, 29, 16, 24]]).T
        # 4 rounds: minHW =  4  [  4  4  4  4 ]
        # 5 rounds: minHW =  6  [  6  8  6  8 ]
        # 6 rounds: minHW =  9  [  9 12  9 12 ]
        # 7 rounds: minHW = 16  [ 16 24 16 24 ]
        # 8 rounds: minHW = 32  [ 32 32 32 32 ]
        # 9 rounds: minHW = 32  [ 32 32 32 32 ]
        # 10 rounds: minHW = 32  [ 32 32 32 32 ]
        # 11 rounds: minHW = 32  [ 32 32 32 32 ]
    }

    SKEIN_KS_PARITY = {
        64: numpy.uint64(0x1BD11BDAA9FC1A22),
        32: numpy.uint32(0x1BD11BDA)
    }

    R = r123_enum_threefry[(W, N)]

    rotate = lambda r_idx, n_idx, x_idx: \
        "((X.v[{x}] << {lshift}) | (X.v[{x}] >> {rshift}))".format(
            x=x_idx,
            lshift=R[r_idx, n_idx] % W,
            rshift=(W - R[r_idx, n_idx]) % W)
%>

WITHIN_KERNEL CBRNG_ARGUMENT rng_threefry(const int thread_id, const CBRNG_ARGUMENT counter)
{
    %for i in range(N):
    const ${ctype} key${i} = ${key[i]}
        %if i == N - 1:
        + thread_id
        %endif
        ;
    %endfor

    <%
        last_k = SKEIN_KS_PARITY[W].copy()
        for i in range(N-1):
            last_k ^= key[i]
    %>
    //const ${ctype} key${N} = ${last_k} ^ key${N-1};
    const ${ctype} key${N} = ${SKEIN_KS_PARITY[W]}
    %for i in range(N):
    ^ key${i}
    %endfor
    ;

    CBRNG_ARGUMENT X;
    %for i in range(N):
    X.v[${i}] = counter.v[${i}];
    %endfor

    // Insert initial key before round 0
    %for i in range(N):
    X.v[${i}] += key${i};
    %endfor

    %for rnd in range(rng_params.rounds):
    { // round ${rnd}
    <%
        R_idx = rnd % 8
    %>
    %if N == 2:
        X.v[0] += X.v[1];
        X.v[1] = ${rotate(R_idx, 0, 1)};
        X.v[1] ^= X.v[0];
    %else:
    <%
        idx1 = 1 if rnd % 2 == 0 else 3
        idx2 = 3 if rnd % 2 == 0 else 1
    %>
        X.v[0] += X.v[${idx1}];
        X.v[${idx1}] = ${rotate(R_idx, 0, idx1)};
        X.v[${idx1}] ^= X.v[0];

        X.v[2] += X.v[${idx2}];
        X.v[${idx2}] = ${rotate(R_idx, 1, idx2)};
        X.v[${idx2}] ^= X.v[2];
    %endif

    %if rnd % 4 == 3:
    %for i in range(N):
        X.v[${i}] += key${(rnd // 4 + i + 1) % (N + 1)};
    %endfor
        X.v[${N-1}] += ${rnd // 4 + 1};
    %endif
    }
    %endfor

    return X;
}
</%def>


<%def name="rng_philox(rng_params)">
<%
    N = rng_params.words
    W = rng_params.bitness
    rounds = rng_params.rounds
    key = rng_params.key

    dtype = numpy.uint32 if W == 32 else numpy.uint64
    ctype = dtypes.ctype(dtype)

    PHILOX_W = {
        64: [
            numpy.uint64(0x9E3779B97F4A7C15), # golden ratio
            numpy.uint64(0xBB67AE8584CAA73B) # sqrt(3)-1
        ],
        32: [
            numpy.uint32(0x9E3779B9), # golden ratio
            numpy.uint32(0xBB67AE85) # sqrt(3)-1
        ]
    }

    PHILOX_M = {
        (64,2): [numpy.uint64(0xD2B74407B1CE6E93)],
        (64,4): [numpy.uint64(0xD2E7470EE14C6C93), numpy.uint64(0xCA5A826395121157)],
        (32,2): [numpy.uint32(0xD256D193)],
        (32,4): [numpy.uint32(0xD2511F53), numpy.uint32(0xCD9E8D57)]
    }
%>

WITHIN_KERNEL INLINE ${ctype} mulhilo(${ctype} *hip, ${ctype} a, ${ctype} b)
{
%if W == 32:
<%
    d_ctype = dtypes.ctype(numpy.uint64)
%>
    ${d_ctype} product = ((${d_ctype})a)*((${d_ctype})b);
    *hip = product >> ${W};
    return (${ctype})product;
%else:
#ifdef CUDA
    *hip = __umul64hi(a, b);
#else
    *hip = mul_hi(a, b);
#endif
    return a*b;
%endif
}


<%def name="philox_round(rnd)">
<%
    # bump key
    with helpers.ignore_integer_overflow():
        key0 = key[0] + PHILOX_W[W][0] * numpy.cast[dtype](rnd)
        if N == 4:
            key1 = key[1] + PHILOX_W[W][1] * numpy.cast[dtype](rnd)
%>
{
%if N == 2:
    ${ctype} hi;
    ${ctype} lo = mulhilo(&hi, ${PHILOX_M[(W,N)][0]}, X.v[0]);
    X.v[0] = hi ^ (${key0} + (${ctype})thread_id) ^ X.v[1];
    X.v[1] = lo;
%else:
    ${ctype} hi0, hi1;
    ${ctype} lo0 = mulhilo(&hi0, ${PHILOX_M[(W,N)][0]}, X.v[0]);
    ${ctype} lo1 = mulhilo(&hi1, ${PHILOX_M[(W,N)][1]}, X.v[2]);
    X.v[0] = hi1 ^ X.v[1] ^ ${key0};
    X.v[1] = lo1;
    X.v[2] = hi0 ^ X.v[3] ^ (${key1} + (${ctype})thread_id);
    X.v[3] = lo0;
%endif
}
</%def>

WITHIN_KERNEL CBRNG_ARGUMENT rng_philox(const int thread_id, const CBRNG_ARGUMENT counter)
{
    CBRNG_ARGUMENT X;
    %for i in range(N):
    X.v[${i}] = counter.v[${i}];
    %endfor

    // round
    %for rnd in range(rng_params.rounds):
        // round ${rnd}
        ${philox_round(rnd)}
    %endfor

    return X;
}
</%def>


<%def name="distribution_uniform_integer(dtype, distr_params)">
<%
    ctype = dtypes.ctype(dtype)
    num = distr_params.max - distr_params.min

    if num <= 2 ** 32:
        raw_ctype = dtypes.ctype(numpy.uint32)
        raw_func = 'get_raw_uint32'
        max_num = 2 ** 32
    else:
        raw_ctype = dtypes.ctype(numpy.uint64)
        raw_func = 'get_raw_uint64'
        max_num = 2 ** 64
%>
WITHIN_KERNEL ${ctype} distribution_uniform_integer(LOCAL_STATE *state)
{
    ${raw_ctype} non_offset = 0;

    %if max_num % num == 0:
    ${raw_ctype} t = ${raw_func}(state);
    non_offset = t / ${max_num // num};
    %else:
    while(1)
    {
        ${raw_ctype} t = ${raw_func}(state);
        if (t < ${max_num - max_num % num})
        {
            non_offset = t / ${max_num // num};
            break;
        }
    }
    %endif

    return (${ctype})non_offset + (${ctype})${distr_params.min};
}
</%def>


<%def name="distribution_uniform_float(dtype, distr_params)">
<%
    ctype = dtypes.ctype(dtype)
    bitness = 64 if dtypes.is_double(dtype) else 32
    raw_func = 'get_raw_uint' + str(bitness)
    raw_max = dtypes.c_constant(2 ** bitness, dtype)
%>
WITHIN_KERNEL ${ctype} distribution_uniform_float(LOCAL_STATE *state)
{
    ${ctype} normalized = (${ctype})${raw_func}(state) / ${raw_max};
    return normalized *
        (${dtypes.c_constant(distr_params.max - distr_params.min, dtype)}) +
        (${dtypes.c_constant(distr_params.min, dtype)});
}
</%def>


<%def name="distribution_normal_bm(dtype, distr_params)">
<%
    dtype2 = dtypes.complex_for(dtype)
    ctype = dtypes.ctype(dtype)
    ctype2 = dtypes.ctype(dtype2)
%>

${distribution_uniform_float(dtype, helpers.AttrDict(min=0, max=1))}

WITHIN_KERNEL ${ctype2} distribution_normal_bm(LOCAL_STATE *state)
{
    ${ctype} u1 = distribution_uniform_float(state);
    ${ctype} u2 = distribution_uniform_float(state);

    ${ctype} ang = ${dtypes.c_constant(2.0 * numpy.pi, dtype)} * u2;
    ${ctype} c_ang = cos(ang);
    ${ctype} s_ang = sin(ang);
    ${ctype} coeff = sqrt(${dtypes.c_constant(-2.0, dtype)} * log(u1)) *
        (${dtypes.c_constant(distr_params.std, dtype)});

    return COMPLEX_CTR(${ctype2})(
        coeff * c_ang + (${dtypes.c_constant(distr_params.mean, dtype)}),
        coeff * s_ang + (${dtypes.c_constant(distr_params.mean, dtype)}));
}
</%def>


<%def name="distribution_gamma(dtype, distr_params)">
<%
    dtype2 = dtypes.complex_for(dtype)
    ctype = dtypes.ctype(dtype)
    ctype2 = dtypes.ctype(dtype2)
%>

${distribution_normal_bm(dtype, helpers.AttrDict(mean=0, std=1))}

WITHIN_KERNEL ${ctype} distribution_gamma(LOCAL_STATE *state)
{
    <%
        d = distr_params.shape - 1. / 3
        c = 1 / numpy.sqrt(9 * d)
        scale = dtypes.c_constant(distr_params.scale, dtype)
    %>

    ${ctype2} rand_normal;
    bool normals_need_regen = true;

    const ${ctype} d = ${dtypes.c_constant(d, dtype)};
    const ${ctype} c = ${dtypes.c_constant(c, dtype)};

    for (;;)
    {
        ${ctype} X, V, U;

        do
        {
            if (normals_need_regen)
            {
                rand_normal = distribution_normal_bm(state);
                X = rand_normal.x;
            }
            else
            {
                X = rand_normal.y;
            }

            V = 1.0 + c * X;
        } while (V <= 0.0);

        V = V * V * V;
        U = distribution_uniform_float(state);
        if (U < 1.0 - 0.0331 * (X * X) * (X * X)) return (d * V) * (${scale});
        if (log(U) < 0.5 * X * X + d * (1. - V + log(V))) return (d * V) * (${scale});
    }
}
</%def>


<%def name="cbrng(new_counters, randoms, old_counters)">

<%
    uint32 = dtypes.ctype(numpy.uint32)
    uint64 = dtypes.ctype(numpy.uint64)
    rng_dtype = numpy.uint32 if rng_params.bitness == 32 else numpy.uint64
    rng_ctype = dtypes.ctype(rng_dtype)
    output_len = rng_params.words
    output_len_words = output_len * (1 if rng_params.bitness == 32 else 2)

    rng_func_name = 'rng_' + rng
    rng_func_body = getattr(local, rng_func_name)

    distr_func_name = 'distribution_' + distribution
    distr_func_body = getattr(local, distr_func_name)

    randoms_per_call = dict(
        uniform_integer=1,
        uniform_float=1,
        normal_bm=2,
        gamma=1,
        )[distribution]
%>

typedef struct _CBRNG_ARGUMENT
{
    ${rng_ctype} v[${output_len}];
} CBRNG_ARGUMENT;

typedef struct _LOCAL_STATE
{
    CBRNG_ARGUMENT counter;
    union {
        CBRNG_ARGUMENT buffer;
        ${uint32} buffer_word[${output_len_words}];
    };
    int buffer_word_cursor;
} LOCAL_STATE;

${rng_func_body(rng_params)}


WITHIN_KERNEL void bump_counter(LOCAL_STATE *state)
{
    %for i in range(output_len-1, 0, -1):
    state->counter.v[${i}] += 1;
    if (state->counter.v[${i}] == 0)
    {
    %endfor
    state->counter.v[0] += 1;
    %for i in range(output_len-1, 0, -1):
    }
    %endfor
}


WITHIN_KERNEL void refill_buffer(LOCAL_STATE *state)
{
    state->buffer = ${rng_func_name}(virtual_global_flat_id(), state->counter);
    bump_counter(state);
    state->buffer_word_cursor = 0;
}


WITHIN_KERNEL ${uint32} get_raw_uint32(LOCAL_STATE *state)
{
    if (state->buffer_word_cursor == ${output_len_words})
    {
        refill_buffer(state);
    }

    int cur = state->buffer_word_cursor;
    state->buffer_word_cursor += 1;
    return state->buffer_word[cur];
}


WITHIN_KERNEL ${uint64} get_raw_uint64(LOCAL_STATE *state)
{
    if (state->buffer_word_cursor >= ${output_len_words} - 1)
    {
        refill_buffer(state);
    }

    int cur = state->buffer_word_cursor;
    state->buffer_word_cursor += 2;
    %if rng_params.bitness == 64:
    return state->buffer.v[cur / 2];
    %else:
    ${uint32} hi = state->buffer_word[cur];
    ${uint32} lo = state->buffer_word[cur+1];
    return ((${uint64})hi << 32) + (${uint64})lo;
    %endif
}

${distr_func_body(randoms.dtype, distribution_params)}


${kernel_definition}
{
    VIRTUAL_SKIP_THREADS;

    const int idx = virtual_global_flat_id();

    LOCAL_STATE local_state;
    %for i in range(output_len):
    local_state.counter.v[${i}] = ${old_counters.load_combined_idx(counters_slices)}(idx, ${i});
    %endfor
    refill_buffer(&local_state);

    %if randoms_per_call == 1 and dtypes.is_complex(randoms.dtype):
    for (int i = 0; i < ${batch}; i++)
    {
        ${randoms.store_combined_idx(randoms_slices)}(
            i, idx,
            COMPLEX_CTR(${randoms.ctype})(
                ${distr_func_name}(&local_state),
                ${distr_func_name}(&local_state)));
    }
    %elif randoms_per_call == 1 or (randoms_per_call == 2 and dtypes.is_complex(randoms.dtype)):
    for (int i = 0; i < ${batch}; i++)
    {
        ${randoms.store_combined_idx(randoms_slices)}(
            i, idx, ${distr_func_name}(&local_state));
    }
    %elif randoms_per_call == 2:
    for (int i = 0; i < ${batch // 2}; i++)
    {
        ${randoms.ctype}2 r = ${distr_func_name}(&local_state);
        ${randoms.store_combined_idx(randoms_slices)}(i * 2, idx, r.x);
        ${randoms.store_combined_idx(randoms_slices)}(i * 2 + 1, idx, r.y);
    }
    %elif batch % 2 != 0:
    {
        ${randoms.ctype}2 r = ${distr_func_name}(&local_state);
        ${randoms.store_combined_idx(randoms_slices)}(i * 2, idx, r.x);
    }
    %else:
    <%
        raise NotImplementedError()
    %>
    %endif

    if (local_state.buffer_word_cursor > 0 && local_state.buffer_word_cursor < ${output_len})
        bump_counter(&local_state);

    %for i in range(output_len):
    ${new_counters.store_combined_idx(counters_slices)}(idx, ${i}, local_state.counter.v[${i}]);
    %endfor
}
</%def>
