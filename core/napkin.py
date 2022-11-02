import time
import math
import pprint
from decimal import *

SECONDS_PER_YEAR = 365 * 24 * 60 * 60
SECONDS_PER_BLOCK = 13
BLOCKS_PER_YEAR = int(SECONDS_PER_YEAR / SECONDS_PER_BLOCK)

# mapping(address => uint256) public borrows;
BORROWS_BITS = 256
# PackedSlot.borrowIndexTimestamp
BORROW_INDEX_TIMESTAMP_BITS = 32
BORROW_INDEX_TIMESTAMP_MAX = 2 ** BORROW_INDEX_TIMESTAMP_BITS - 1
DT_YEARS = (BORROW_INDEX_TIMESTAMP_MAX - int(time.time())) / SECONDS_PER_YEAR
assert DT_YEARS >= 10


def check(
    asset_decimals,
    total_borrows_bits,
    total_borrows_precision,
    borrow_index_bits,
    borrow_index_precision,
    accrual_factor_precision,
):
    # to fix: decrease asset_decimals
    assert asset_decimals <= 18, 'asset_decimals is unreasonably large'

    # to fix: ensure these 3 values add up to 256
    assert total_borrows_bits + borrow_index_bits + BORROW_INDEX_TIMESTAMP_BITS == 256, 'borrow data should be stored efficiently'

    total_borrows_max = 2 ** total_borrows_bits - 1
    total_borrows_max_units = total_borrows_max / 10 ** (total_borrows_precision + asset_decimals)
    total_borrows_max_units_oom = math.log10(total_borrows_max_units)
    # to fix: increase total_borrows_bits or decrease total_borrows_precision
    # TODO (simpler) --- total_borrows_max >= 10 ** (12 + total_borrows_precision + asset_decimals)
    assert total_borrows_max_units_oom >= 12, f'total_borrows should be able to handle 1 trillion units of asset --- current max is 10^{total_borrows_max_units_oom}'

    borrow_index_max = 2 ** borrow_index_bits - 1
    borrow_index_min = 10 ** borrow_index_precision
    apr_max = math.log(borrow_index_max / borrow_index_min) / DT_YEARS
    apy_max = math.exp(apr_max) - 1
    # to fix: decrease borrow_index_timestamp_bits, increase borrow_index_bits, or decrease borrow_index_precision
    assert 100 * apy_max > 25.0, f'borrow_index should handle at least 25% APY over the protocol\'s lifetime --- current max is {100 * apy_max:0.2f}'

    accrual_factor_scaler = Decimal(10 ** accrual_factor_precision)
    min_nonzero_borrow_index_growth_factor = (accrual_factor_scaler + 1) / accrual_factor_scaler
    borrow_index_a = math.floor(borrow_index_min * min_nonzero_borrow_index_growth_factor)
    borrow_index_b = math.floor(borrow_index_max / min_nonzero_borrow_index_growth_factor)
    assert borrow_index_a > borrow_index_min, 'borrow_index should grow even if accrual_factor is only 1'

    total_borrows_min = 10 ** total_borrows_precision
    min_accrued_interest = math.floor(total_borrows_min / accrual_factor_scaler)
    assert min_accrued_interest > 0, 'total_borrows should grow (i.e. accrued interest should be non-zero) even if accrual_factor is only 1'

    temp = Decimal(borrow_index_min)
    for _ in range(BLOCKS_PER_YEAR):
        temp = Decimal(math.floor(temp * min_nonzero_borrow_index_growth_factor))
    apy_min = temp / Decimal(borrow_index_min) - 1
    # to fix: increase borrow_index_precision
    assert 100 * apy_min < 0.01, f'borrow_index should allow for APY as low as 0.01% --- current min is {100 * apy_min:0.2f}%'

    # temp = Decimal(10 ** (asset_decimals + total_borrows_precision))
    # for _ in range(BLOCKS_PER_YEAR):
    #     temp += Decimal(math.floor(temp / accrual_factor_scaler))
    # apy_min_2 = temp / Decimal(10 ** (asset_decimals + total_borrows_precision)) - 1
    # assert 100 * apy_min_2 < 0.01, f'total_borrows should allow for APY as low as 0.01% --- current min is {100 * apy_min_2:0.2f}%'

    borrows_max = 2 ** BORROWS_BITS - 1
    borrows_scaler = Decimal(borrow_index_min * borrows_max / total_borrows_max)
    assert math.floor(borrows_scaler / borrow_index_min) > math.floor(borrows_scaler / borrow_index_a), 'borrows should change even with the smallest change in borrow_index'
    assert math.floor(borrows_scaler / borrow_index_b) > math.floor(borrows_scaler / borrow_index_max), 'borrows should change even with the smallest change in borrow_index'

    return {
        'min APY': float(100 * apy_min),
        'max APY': float(100 * apy_max),
        'max totalBorrows': f'10^{total_borrows_max_units_oom:.1f}',
        'min accruedInterest': min_accrued_interest,
        'init borrowIndex': borrow_index_min,
        'borrows_scaler': int(borrows_scaler),
    }


for asset_decimals in [6, 8, 18]:
    pprint.pp(check(
        asset_decimals=asset_decimals,
        total_borrows_bits=144,
        total_borrows_precision=12,
        borrow_index_bits=80,
        borrow_index_precision=12,
        accrual_factor_precision=12
    ), indent=4)

print(math.floor(Decimal(1e12) / Decimal(math.e)))
