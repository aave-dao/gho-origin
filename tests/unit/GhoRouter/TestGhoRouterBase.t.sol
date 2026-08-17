// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import '../TestGhoBase.t.sol';

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import {IGhoRouter} from 'src/contracts/misc/interfaces/IGhoRouter.sol';
import {MockBadGsm} from '../../mocks/MockBadGsm.sol';
import {MockBadStata} from '../../mocks/MockBadStataToken.sol';

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

  function setUp() public {
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

  function _mintSgho(uint256 amount) internal {
    _dealAndApprove(address(GHO_TOKEN), address(SGHO), amount);
    vm.prank(USER);
    SGHO.deposit(amount, USER);
  }
}
