import time
import math
import pprint
import random
from decimal import *

SECONDS_PER_YEAR = 365 * 24 * 60 * 60
SECONDS_PER_BLOCK = 1
BLOCKS_PER_YEAR = int(SECONDS_PER_YEAR / SECONDS_PER_BLOCK)

# mapping(address => uint256) public borrows;
BORROWS_BITS = 256
# PackedSlot.borrowIndexTimestamp
BORROW_INDEX_TIMESTAMP_BITS = 32
BORROW_INDEX_TIMESTAMP_MAX = 2 ** BORROW_INDEX_TIMESTAMP_BITS - 1
DT_YEARS = (BORROW_INDEX_TIMESTAMP_MAX - int(time.time())) / SECONDS_PER_YEAR
assert DT_YEARS >= 10

RESERVE_DIVISOR = 8


def to_borrows(borrow_base, borrow_index, borrow_scaler, accrual_factor_scaler, precise=True):
    if precise:
        return math.floor(accrual_factor_scaler * borrow_base * borrow_index / borrow_scaler)
    return math.floor(borrow_base * borrow_index / borrow_scaler)

def to_base(borrows, borrow_index, borrow_scaler, accrual_factor_scaler, precise=True):
    if precise:
        borrows /= accrual_factor_scaler
    return math.floor(borrows * borrow_scaler / borrow_index)



def check(
    asset_decimals,
    balance_bits,
    total_supply_bits,
    total_supply_extra_precision,
    borrow_base_bits,
    borrow_index_bits,
    borrow_index_precision,
    accrual_factor_precision,
):
    # to fix: decrease asset_decimals
    assert asset_decimals <= 18, 'asset_decimals is unreasonably large'

    # to fix: ensure these slots add up to 256
    assert BORROW_INDEX_TIMESTAMP_BITS + balance_bits + total_supply_bits == 256, 'slot0 should be stored efficiently'
    assert borrow_base_bits + borrow_index_bits == 256, 'slot1 should be stored efficiently'

    borrow_base_max = Decimal(2 ** borrow_base_bits - 1)
    borrow_index_max = Decimal(2 ** borrow_index_bits - 1)
    borrow_index_min = Decimal(1 * 10 ** borrow_index_precision)
    accrual_factor_scaler = Decimal(10 ** accrual_factor_precision)
    borrow_scaler = borrow_index_max * accrual_factor_scaler
    borrow_base_min_nonzero = 1 * borrow_scaler / borrow_index_min

    total_borrows_max = to_borrows(borrow_base_max, borrow_index_min, borrow_scaler, accrual_factor_scaler, precise=False)
    total_borrows_max_units = total_borrows_max / 10 ** asset_decimals
    total_borrows_max_units_oom = math.log10(total_borrows_max_units)
    # to fix: increase total_borrows_bits or decrease total_borrows_precision
    # TODO (simpler) --- total_borrows_max >= 10 ** (12 + total_borrows_precision + asset_decimals)
    assert total_borrows_max_units_oom >= 12, f'total_borrows should be able to handle 1 trillion units of asset --- current max is 10^{total_borrows_max_units_oom}'

    apr_max = math.log(borrow_index_max / borrow_index_min) / DT_YEARS
    apy_max = math.exp(apr_max) - 1
    spy_max = math.exp(apr_max / SECONDS_PER_YEAR) - 1
    # to fix: decrease borrow_index_timestamp_bits, increase borrow_index_bits, or decrease borrow_index_precision
    assert 100 * apy_max > 25.0, f'borrow_index should handle at least 25% APY over the protocol\'s lifetime --- current max is {100 * apy_max:0.2f}'

    min_nonzero_borrow_index_growth_factor = (accrual_factor_scaler + 1) / accrual_factor_scaler
    borrow_index_a = math.floor(borrow_index_min * min_nonzero_borrow_index_growth_factor)
    borrow_index_b = math.floor(borrow_index_max / min_nonzero_borrow_index_growth_factor)
    assert borrow_index_a > borrow_index_min, 'borrow_index should grow even if accrual_factor is only 1'

    total_borrows_min = to_borrows(borrow_base_min_nonzero, borrow_index_min, borrow_scaler, accrual_factor_scaler, precise=True)
    total_borrows_a = to_borrows(borrow_base_min_nonzero, borrow_index_a, borrow_scaler, accrual_factor_scaler, precise=True)
    min_accrued_interest = total_borrows_a - total_borrows_min
    assert min_accrued_interest > 0, 'total_borrows should grow (i.e. accrued interest should be non-zero) even if accrual_factor is only 1'

    apy_min = min_nonzero_borrow_index_growth_factor ** BLOCKS_PER_YEAR - 1
    # to fix: increase accrual_factor_precision
    assert 100 * apy_min < 0.05, f'borrow_index should allow for APY as low as 0.05% --- current min is {100 * apy_min:0.2f}%'

    # temp = Decimal(10 ** (asset_decimals + total_borrows_precision))
    # for _ in range(BLOCKS_PER_YEAR):
    #     temp += Decimal(math.floor(temp / accrual_factor_scaler))
    # apy_min_2 = temp / Decimal(10 ** (asset_decimals + total_borrows_precision)) - 1
    # assert 100 * apy_min_2 < 0.01, f'total_borrows should allow for APY as low as 0.01% --- current min is {100 * apy_min_2:0.2f}%'

    assert math.floor(borrow_scaler / borrow_index_min) > math.floor(borrow_scaler / borrow_index_a), '(a) borrows should change even with the smallest change in borrow_index'
    assert math.floor(borrow_scaler / borrow_index_b) > math.floor(borrow_scaler / borrow_index_max), '(b) borrows should change even with the smallest change in borrow_index'
    for _ in range(100000):
        temp0 = Decimal(random.getrandbits(borrow_index_bits) - 1)
        temp1 = temp0 * min_nonzero_borrow_index_growth_factor
        assert math.floor(borrow_scaler / temp0) > math.floor(borrow_scaler / temp1), '(c) borrows should change even with the smallest change in borrow_index'

    one_unit = Decimal(10 ** asset_decimals)
    inventory = one_unit
    total_supply = inventory * Decimal(10 ** total_supply_extra_precision)
    interest = Decimal(1)
    while True:
        interest += 1
        total_supply_new = total_supply * (inventory + interest) / (inventory + interest - math.floor(interest / RESERVE_DIVISOR))
        if math.floor(total_supply_new) > total_supply:
            break
    assert interest < one_unit / 1000, 'Reserves should increase even if accrued interest is just 1 one-thousandth of a unit'

    total_supply = inventory * Decimal(10 ** total_supply_extra_precision) / 10
    interest = Decimal(1)
    while True:
        interest += 1
        total_supply_new = total_supply * (inventory + interest) / (inventory + interest - math.floor(interest / RESERVE_DIVISOR))
        if math.floor(total_supply_new) > total_supply:
            break
    assert interest < one_unit / 1000, 'Reserves should increase even if accrued interest is just 1 one-thousandth of a unit, even after precision of total supply starts to fall off'

    return {
        'min APY': float(100 * apy_min),
        'max APY': float(100 * apy_max),
        'max yield per second * 1e12': float(1e12 * spy_max),
        'max totalBorrows': f'10^{total_borrows_max_units_oom:.1f}',
        'max balance': f'10^{math.log10((2 ** balance_bits - 1) / 10 ** asset_decimals):.1f}',
        'max total supply': f'10^{math.log10((2 ** total_supply_bits - 1) / 10 ** (asset_decimals + total_supply_extra_precision)):.1f}',
        'min accruedInterest': min_accrued_interest,
        'init borrowIndex': borrow_index_min,
        'borrows_scaler': int(borrow_scaler),
    }


for asset_decimals in [6, 8, 18]:
    pprint.pp(check(
        asset_decimals=asset_decimals,
        balance_bits=112,
        total_supply_bits=112,
        total_supply_extra_precision=0,#3,#18-asset_decimals,
        borrow_base_bits=184,
        borrow_index_bits=72,
        borrow_index_precision=12,
        accrual_factor_precision=12
    ), indent=4)
