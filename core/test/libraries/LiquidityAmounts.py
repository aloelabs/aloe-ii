import sys
from decimal import Decimal


Q96 = Decimal(2 ** 96)


if __name__ == '__main__':
    sqrtPrice = Decimal(sys.argv[1])
    sqrtLower = Decimal(sys.argv[2])
    sqrtUpper = Decimal(sys.argv[3])
    liquidity = Decimal(sys.argv[4])

    value0 = Decimal(0)
    value1 = Decimal(0)

    if sqrtPrice <= sqrtLower:
        value0 = liquidity * Q96 * (sqrtUpper - sqrtLower) / sqrtUpper / sqrtLower * sqrtPrice / Q96 * sqrtPrice / Q96
    elif sqrtPrice < sqrtUpper:
        value0 = liquidity * Q96 * (sqrtUpper - sqrtPrice) / sqrtUpper / Q96 * sqrtPrice / Q96
        value1 = liquidity * (sqrtPrice - sqrtLower) / Q96
    else:
        value1 = liquidity * (sqrtUpper - sqrtLower) / Q96

    out0 = hex(int(value0))[2:].zfill(64)
    out1 = hex(int(value1))[2:].zfill(64)
    print(f'0x{out0}{out1}')
