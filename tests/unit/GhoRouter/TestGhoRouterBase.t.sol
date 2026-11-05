// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import '../TestGhoBase.t.sol';

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import {IWithGuardian} from 'solidity-utils/contracts/access-control/interfaces/IWithGuardian.sol';

import {IGhoRouter} from 'src/contracts/misc/interfaces/IGhoRouter.sol';
import {MockBadGsm} from '../../mocks/MockBadGsm.sol';
import {MockBadStata} from '../../mocks/MockBadStata.sol';

/**
 * @title GhoRouterTest
 * @notice Unit tests for GhoRouter
 * @dev Run with: forge test --match-path test/unit/GhoRouter/GhoRouterTest.t.sol -vvv
 */
contract TestGhoRouterBase is TestGhoBase {
  uint256 public constant MAX_FUZZ_AMOUNT_6_DECIMALS = 10_000_000e6;
  uint256 public constant MAX_FUZZ_AMOUNT_18_DECIMALS = 10_000_000 ether;

  address public immutable USER = makeAddr('0xF00DBA11');
  address public immutable RECIPIENT = makeAddr('0xCAFEF00D');

  uint256 internal buyFee = DEFAULT_GSM_BUY_FEE;
  uint256 internal sellFee = DEFAULT_GSM_SELL_FEE;

  function setUp() public virtual {
    GHO_ROUTER.allowGsm(address(GHO_GSM_4626));
    GHO_ROUTER.setTokenToStata(address(USDX_TOKEN), address(USDX_4626_TOKEN));

    deal(address(USDX_TOKEN), address(this), MAX_FUZZ_AMOUNT_6_DECIMALS);
    USDX_TOKEN.approve(address(USDX_4626_TOKEN), MAX_FUZZ_AMOUNT_6_DECIMALS);
    USDX_4626_TOKEN.deposit(MAX_FUZZ_AMOUNT_6_DECIMALS, address(this));

    USDX_4626_TOKEN.approve(address(GHO_GSM_4626), MAX_FUZZ_AMOUNT_6_DECIMALS);
    GHO_GSM_4626.sellAsset(MAX_FUZZ_AMOUNT_6_DECIMALS, address(this));
  }

  function _dealAndApprove(address token, address spender, uint256 amount) internal {
    deal(token, USER, amount);
    vm.prank(USER);
    IERC20(token).approve(spender, amount);
  }

  function _setUsdxVaultRate(uint256 numerator, uint256 denominator) internal {
    uint256 vaultAssets = USDX_TOKEN.balanceOf(address(USDX_4626_TOKEN));
    deal(address(USDX_TOKEN), address(USDX_4626_TOKEN), (vaultAssets * numerator) / denominator);
  }

  function _setGsmFees(uint256 newBuyFee, uint256 newSellFee) internal {
    address feeStrategy = newBuyFee == 0 && newSellFee == 0
      ? address(0)
      : address(new FixedFeeStrategy(newBuyFee, newSellFee));
    GHO_GSM.updateFeeStrategy(feeStrategy);
    GHO_GSM_4626.updateFeeStrategy(feeStrategy);
    buyFee = newBuyFee;
    sellFee = newSellFee;
  }

  function _allowAndFundPlainGsm() internal {
    GHO_ROUTER.allowGsm(address(GHO_GSM));
    deal(address(USDX_TOKEN), address(this), MAX_FUZZ_AMOUNT_6_DECIMALS);
    USDX_TOKEN.approve(address(GHO_GSM), MAX_FUZZ_AMOUNT_6_DECIMALS);
    GHO_GSM.sellAsset(MAX_FUZZ_AMOUNT_6_DECIMALS, address(this));
  }

  function _assertRouterEmpty() internal view {
    assertEq(GHO_TOKEN.balanceOf(address(GHO_ROUTER)), 0, 'Router should hold no GHO');
    assertEq(IERC20(address(SGHO)).balanceOf(address(GHO_ROUTER)), 0, 'Router should hold no sGHO');
    assertEq(USDX_TOKEN.balanceOf(address(GHO_ROUTER)), 0, 'Router should hold no USDX_TOKEN');
    assertEq(USDX_4626_TOKEN.balanceOf(address(GHO_ROUTER)), 0, 'Router should hold no stata');
  }

  function _assertNoRouterAllowances() internal view {
    address router = address(GHO_ROUTER);
    assertEq(USDX_TOKEN.allowance(router, address(GHO_GSM)), 0, 'USDX_TOKEN -> GSM allowance');
    assertEq(
      USDX_TOKEN.allowance(router, address(USDX_4626_TOKEN)),
      0,
      'USDX_TOKEN -> stata allowance'
    );
    assertEq(
      USDX_4626_TOKEN.allowance(router, address(GHO_GSM_4626)),
      0,
      'stata -> GSM_4626 allowance'
    );
    assertEq(GHO_TOKEN.allowance(router, address(GHO_GSM)), 0, 'GHO -> GSM allowance');
    assertEq(GHO_TOKEN.allowance(router, address(GHO_GSM_4626)), 0, 'GHO -> GSM_4626 allowance');
    assertEq(GHO_TOKEN.allowance(router, address(SGHO)), 0, 'GHO -> sGHO allowance');
  }

  /// @dev GHO a GSM charges to buy assets worth `grossGho`: gross plus buy fee rounded up
  function _ghoForBuy(uint256 grossGho) internal view returns (uint256) {
    return grossGho + Math.mulDiv(grossGho, buyFee, 1e4, Math.Rounding.Ceil);
  }

  /// @dev GHO a GSM pays out for assets worth `grossGho`: gross minus sell fee rounded up
  function _ghoFromSell(uint256 grossGho) internal view returns (uint256) {
    return grossGho - Math.mulDiv(grossGho, sellFee, 1e4, Math.Rounding.Ceil);
  }

  /// @dev Underlying-asset amount a GSM sells for `ghoAmount`: gross after buy fee, scaled 18 -> 6 decimals
  function _usdxForBuy(uint256 ghoAmount) internal view returns (uint256) {
    return Math.mulDiv(ghoAmount, 1e4, 1e4 + buyFee) / 1e12;
  }

  function _mintSgho(uint256 amount) internal {
    _dealAndApprove(address(GHO_TOKEN), address(SGHO), amount);
    vm.prank(USER);
    SGHO.deposit(amount, USER);
  }
}
