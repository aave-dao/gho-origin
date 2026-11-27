// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC4626} from 'openzeppelin-contracts/contracts/interfaces/IERC4626.sol';
import {IAccessControl} from 'openzeppelin-contracts/contracts/access/IAccessControl.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import {SafeCast} from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {TransparentUpgradeableProxy} from 'openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {ICollector} from 'aave-v3-origin/contracts/treasury/ICollector.sol';
import {IPool} from 'aave-v3-origin/contracts/interfaces/IPool.sol';
import {IScaledBalanceToken} from 'aave-v3-origin/contracts/interfaces/IScaledBalanceToken.sol';
import {WadRayMath} from 'aave-v3-origin/contracts/protocol/libraries/math/WadRayMath.sol';
import {MathUtils} from 'aave-v3-origin/contracts/protocol/libraries/math/MathUtils.sol';
import {PercentageMath} from 'aave-v3-origin/contracts/protocol/libraries/math/PercentageMath.sol';

import {sGho} from 'src/contracts/sgho/sGho.sol';
import {sGhoInstance} from 'src/contracts/sgho/instances/sGhoInstance.sol';
import {sGhoSteward, IsGhoSteward} from 'src/contracts/misc/sGhoSteward.sol';
import {AaveV3StataEnvironment} from '../../helpers/AaveV3StataEnvironment.sol';
import {MockERC4626} from '../../mocks/MockERC4626.sol';

/// @dev Claims to be the GHO aToken of a real pool, which maps GHO to another aToken
contract FakeAToken {
  address public immutable UNDERLYING_ASSET_ADDRESS;
  IPool public immutable POOL;

  constructor(address underlying, IPool pool) {
    UNDERLYING_ASSET_ADDRESS = underlying;
    POOL = pool;
  }
}

/// @dev Quotes one share more in `previewWithdraw` than `withdraw` burns, as ERC4626 allows
contract RoundingUpVault is MockERC4626 {
  constructor(
    string memory name,
    string memory symbol,
    address asset
  ) MockERC4626(name, symbol, asset) {}

  function previewWithdraw(uint256 assets) public view override returns (uint256) {
    return super.previewWithdraw(assets) + 1;
  }

  function withdraw(
    uint256 assets,
    address receiver,
    address owner
  ) public override returns (uint256) {
    uint256 shares = super.previewWithdraw(assets);
    _withdraw(_msgSender(), receiver, owner, assets, shares);
    return shares;
  }
}

/**
 * @title TestSGhoStewardFunding
 * @notice sGhoSteward funding against a real collector, aToken and static aToken on a local Aave
 * v3 market. WETH stands in for GHO.
 */
contract TestSGhoStewardFunding is Test {
  using SafeCast for uint256;

  uint256 internal constant MAX_FUNDING_AMOUNT = 100_000 ether;
  uint256 internal constant FUNDING_BUFFER_DURATION = 90 days;
  uint16 internal constant SGHO_RATE = 10_00;
  uint256 internal constant DEPOSIT = 1_000 ether;
  uint256 internal constant COLLECTOR_FUNDS = 1_000 ether;

  AaveV3StataEnvironment internal AAVE;
  IERC20 internal GHO;
  sGho internal SGHO;
  sGhoSteward internal STEWARD;
  address internal COLLECTOR;
  address internal A_GHO;
  IERC4626 internal STATA_GHO;
  IERC4626 internal VAULT_GHO;

  address internal governance = makeAddr('governance');
  address internal riskCouncil = makeAddr('riskCouncil');
  address internal user = makeAddr('user');

  function setUp() public {
    AAVE = new AaveV3StataEnvironment();
    AAVE.deploy();
    GHO = IERC20(AAVE.wethToken());
    COLLECTOR = AAVE.collector();
    A_GHO = AAVE.aToken(address(GHO));
    STATA_GHO = IERC4626(AAVE.stataToken(address(GHO)));
    VAULT_GHO = IERC4626(address(new MockERC4626('Vault GHO', 'vGHO', address(GHO))));

    SGHO = sGho(
      address(
        new TransparentUpgradeableProxy(
          address(new sGhoInstance()),
          makeAddr('proxyAdmin'),
          abi.encodeCall(
            sGhoInstance.initialize,
            (
              address(GHO),
              type(uint40).max,
              address(this),
              WadRayMath.RAY.toUint120(),
              block.timestamp.toUint40(),
              SGHO_RATE
            )
          )
        )
      )
    );

    STEWARD = new sGhoSteward({
      owner: governance,
      riskCouncil: riskCouncil,
      sGho: address(SGHO),
      collector: COLLECTOR,
      maxFundingAmount: MAX_FUNDING_AMOUNT,
      fundingBufferDuration: FUNDING_BUFFER_DURATION
    });
    AAVE.grantFundsAdmin(address(STEWARD));

    // Depositors, so sGHO owes more GHO than it holds once yield accrues
    deal(address(GHO), user, DEPOSIT);
    vm.startPrank(user);
    GHO.approve(address(SGHO), DEPOSIT);
    SGHO.deposit(DEPOSIT, user);
    vm.stopPrank();

    // The collector holds GHO, aGHO, static aGHO shares and vault shares
    deal(address(GHO), COLLECTOR, COLLECTOR_FUNDS);
    AAVE.supply(address(GHO), COLLECTOR_FUNDS * 3, address(this));
    AAVE.supply(address(GHO), COLLECTOR_FUNDS, COLLECTOR);
    _depositInto(STATA_GHO, COLLECTOR_FUNDS);
    _depositInto(VAULT_GHO, COLLECTOR_FUNDS);

    vm.warp(block.timestamp + 30 days);
  }

  // ========================================
  // FUNDING SOURCES
  // ========================================

  function test_fundSGho(uint256 amount) external {
    amount = bound(amount, 1, _expectedHeadroom());
    uint256 collectorBefore = GHO.balanceOf(COLLECTOR);

    _assertFunds(address(GHO), amount);

    assertEq(collectorBefore - GHO.balanceOf(COLLECTOR), amount, 'collector GHO');
  }

  /// @dev The collector loses exactly the scaled aToken balance a withdrawal of `amount` burns
  function test_fundSGhoFromAToken(uint256 amount, uint256 elapsed) external {
    _growIndex(bound(elapsed, 0, 365 days));
    amount = bound(amount, 1, _expectedHeadroom());
    uint256 index = AAVE.normalizedIncome(address(GHO));
    uint256 scaledBefore = IScaledBalanceToken(A_GHO).scaledBalanceOf(COLLECTOR);

    _assertFunds(A_GHO, amount);

    assertEq(
      scaledBefore - IScaledBalanceToken(A_GHO).scaledBalanceOf(COLLECTOR),
      Math.mulDiv(amount, WadRayMath.RAY, index, Math.Rounding.Ceil),
      'collector aGHO'
    );
  }

  function test_fundSGhoFromVault_staticAToken(uint256 amount, uint256 elapsed) external {
    _growIndex(bound(elapsed, 0, 365 days));
    amount = bound(amount, 1, _expectedHeadroom());
    uint256 sharesBefore = STATA_GHO.balanceOf(COLLECTOR);
    uint256 expectedShares = STATA_GHO.previewWithdraw(amount);

    _assertFunds(address(STATA_GHO), amount);

    assertEq(sharesBefore - STATA_GHO.balanceOf(COLLECTOR), expectedShares, 'collector shares');
  }

  function test_fundSGhoFromVault_erc4626(uint256 amount) external {
    amount = bound(amount, 1, _expectedHeadroom());
    uint256 sharesBefore = VAULT_GHO.balanceOf(COLLECTOR);
    uint256 expectedShares = VAULT_GHO.previewWithdraw(amount);

    _assertFunds(address(VAULT_GHO), amount);

    assertEq(sharesBefore - VAULT_GHO.balanceOf(COLLECTOR), expectedShares, 'collector shares');
  }

  /// @dev A vault may quote more shares than `withdraw` burns; the rest go back to the collector
  function test_fundSGhoFromVault_returnsUnusedShares() external {
    IERC4626 vault = IERC4626(address(new RoundingUpVault('Vault GHO', 'rvGHO', address(GHO))));
    _depositInto(vault, COLLECTOR_FUNDS);
    uint256 amount = 1 ether;
    uint256 sharesBefore = vault.balanceOf(COLLECTOR);
    uint256 sharesBurned = vault.previewWithdraw(amount) - 1;

    _assertFunds(address(vault), amount);

    assertEq(sharesBefore - vault.balanceOf(COLLECTOR), sharesBurned, 'collector shares');
  }

  // ========================================
  // LIMITS
  // ========================================

  /// @dev Headroom is sGHO liabilities plus 90 days of yield at the current rate, minus its GHO
  function test_headroom() external view {
    uint256 totalAssets = SGHO.totalAssets();
    uint256 balance = GHO.balanceOf(address(SGHO));
    assertGt(totalAssets, balance, 'no shortfall');
    uint256 buffer = (totalAssets * SGHO_RATE * 90 days) / (100_00 * 365 days);
    assertEq(STEWARD.getFundingHeadroom(), totalAssets + buffer - balance, 'headroom');
  }

  function test_fund_upToHeadroom() external {
    uint256 headroom = STEWARD.getFundingHeadroom();

    vm.expectRevert(
      abi.encodeWithSelector(IsGhoSteward.FundingHeadroomExceeded.selector, headroom)
    );
    vm.prank(riskCouncil);
    STEWARD.fundSGho(headroom + 1);

    vm.prank(riskCouncil);
    STEWARD.fundSGho(headroom);
    assertEq(STEWARD.getFundingHeadroom(), 0, 'headroom left');
  }

  function test_revert_fund_overfunded() external {
    deal(address(GHO), address(SGHO), SGHO.totalAssets() * 2);
    assertEq(STEWARD.getFundingHeadroom(), 0, 'headroom');

    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.FundingHeadroomExceeded.selector, 0));
    vm.prank(riskCouncil);
    STEWARD.fundSGho(1);
  }

  function test_revert_fund_aboveMaxFundingAmount() external {
    vm.prank(governance);
    STEWARD.setMaxFundingAmount(1 ether);

    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.FundingAmountExceeded.selector, 1 ether));
    vm.prank(riskCouncil);
    STEWARD.fundSGho(1 ether + 1);

    vm.prank(riskCouncil);
    STEWARD.fundSGho(1 ether);
  }

  function test_revert_fund_zeroAmount() external {
    vm.expectRevert(IsGhoSteward.InvalidAmount.selector);
    vm.prank(riskCouncil);
    STEWARD.fundSGho(0);
  }

  /// @dev A funding is allowed again exactly `MINIMUM_DELAY` after the last one, from any source
  function test_revert_fund_debounce() external {
    vm.prank(riskCouncil);
    STEWARD.fundSGho(1 ether);

    vm.warp(block.timestamp + 1 days - 1);
    vm.expectRevert(IsGhoSteward.DebounceNotRespected.selector);
    vm.prank(riskCouncil);
    STEWARD.fundSGhoFromAToken(A_GHO, 1 ether);

    vm.warp(block.timestamp + 1);
    vm.prank(riskCouncil);
    STEWARD.fundSGhoFromAToken(A_GHO, 1 ether);
    assertEq(STEWARD.getLastFundingTimestamp(), block.timestamp, 'last funding');
  }

  // ========================================
  // ACCESS AND SOURCE VALIDATION
  // ========================================

  function test_revert_fund_notFundingManager(address caller) external {
    vm.assume(caller != riskCouncil);
    bytes memory error = abi.encodeWithSelector(
      IAccessControl.AccessControlUnauthorizedAccount.selector,
      caller,
      STEWARD.FUNDING_MANAGER_ROLE()
    );

    vm.startPrank(caller);
    vm.expectRevert(error);
    STEWARD.fundSGho(1 ether);
    vm.expectRevert(error);
    STEWARD.fundSGhoFromAToken(A_GHO, 1 ether);
    vm.expectRevert(error);
    STEWARD.fundSGhoFromVault(address(STATA_GHO), 1 ether);
    vm.stopPrank();
  }

  function test_revert_fundSGhoFromAToken_otherUnderlying() external {
    address aUsdx = AAVE.aToken(AAVE.usdxToken());

    vm.expectRevert(IsGhoSteward.InvalidFundingSource.selector);
    vm.prank(riskCouncil);
    STEWARD.fundSGhoFromAToken(aUsdx, 1 ether);
  }

  function test_revert_fundSGhoFromAToken_notPoolAToken() external {
    address fake = address(new FakeAToken(address(GHO), IPool(AAVE.pool())));

    vm.expectRevert(IsGhoSteward.InvalidFundingSource.selector);
    vm.prank(riskCouncil);
    STEWARD.fundSGhoFromAToken(fake, 1 ether);
  }

  function test_revert_fundSGhoFromVault_otherAsset() external {
    address stataUsdx = AAVE.stataToken(AAVE.usdxToken());

    vm.expectRevert(IsGhoSteward.InvalidFundingSource.selector);
    vm.prank(riskCouncil);
    STEWARD.fundSGhoFromVault(stataUsdx, 1 ether);
  }

  function test_revert_fund_stewardNotFundsAdmin() external {
    sGhoSteward steward = new sGhoSteward({
      owner: governance,
      riskCouncil: riskCouncil,
      sGho: address(SGHO),
      collector: COLLECTOR,
      maxFundingAmount: MAX_FUNDING_AMOUNT,
      fundingBufferDuration: FUNDING_BUFFER_DURATION
    });

    vm.expectRevert(ICollector.OnlyFundsAdmin.selector);
    vm.prank(riskCouncil);
    steward.fundSGho(1 ether);
  }

  // ========================================
  // MAX FUNDING AMOUNT
  // ========================================

  function test_setMaxFundingAmount() external {
    vm.expectEmit(address(STEWARD));
    emit IsGhoSteward.MaxFundingAmountUpdated(governance, 50_000 ether);
    vm.prank(governance);
    STEWARD.setMaxFundingAmount(50_000 ether);

    assertEq(STEWARD.getMaxFundingAmount(), 50_000 ether, 'max funding amount');
  }

  function test_revert_setMaxFundingAmount_unchanged() external {
    vm.expectRevert(IsGhoSteward.MaxFundingAmountUnchanged.selector);
    vm.prank(governance);
    STEWARD.setMaxFundingAmount(MAX_FUNDING_AMOUNT);
  }

  function test_revert_setMaxFundingAmount_notAdmin() external {
    vm.expectRevert(
      abi.encodeWithSelector(
        IAccessControl.AccessControlUnauthorizedAccount.selector,
        riskCouncil,
        STEWARD.DEFAULT_ADMIN_ROLE()
      )
    );
    vm.prank(riskCouncil);
    STEWARD.setMaxFundingAmount(50_000 ether);
  }

  // ========================================
  // HELPERS
  // ========================================

  /// @dev Funds `amount` from `source` and checks sGHO received exactly that, the steward keeps
  /// nothing, and the funding is recorded
  function _assertFunds(address source, uint256 amount) internal {
    uint256 sGhoBefore = GHO.balanceOf(address(SGHO));

    vm.expectEmit(address(STEWARD));
    emit IsGhoSteward.SGhoFunded(riskCouncil, source, amount);
    vm.prank(riskCouncil);
    if (source == address(GHO)) {
      STEWARD.fundSGho(amount);
    } else if (source == A_GHO) {
      STEWARD.fundSGhoFromAToken(source, amount);
    } else {
      STEWARD.fundSGhoFromVault(source, amount);
    }

    assertEq(GHO.balanceOf(address(SGHO)) - sGhoBefore, amount, 'sGHO GHO');
    assertEq(GHO.balanceOf(address(STEWARD)), 0, 'steward GHO');
    assertEq(IERC20(source).balanceOf(address(STEWARD)), 0, 'steward source');
    assertEq(STEWARD.getLastFundingTimestamp(), block.timestamp, 'last funding');
  }

  /// @dev sGHO liabilities plus 90 days of yield at the current rate, minus the GHO it holds
  function _expectedHeadroom() internal view returns (uint256) {
    uint256 totalAssets = SGHO.totalAssets();
    uint256 buffer = Math.mulDiv(
      totalAssets,
      uint256(SGHO.targetRate()) * FUNDING_BUFFER_DURATION,
      PercentageMath.PERCENTAGE_FACTOR * MathUtils.SECONDS_PER_YEAR
    );
    return totalAssets + buffer - GHO.balanceOf(address(SGHO));
  }

  /// @dev Borrows half the GHO reserve and lets interest accrue, so the aToken index grows
  function _growIndex(uint256 elapsed) internal {
    if (elapsed == 0) return;
    AAVE.borrow(address(GHO), AAVE.availableLiquidity(address(GHO)) / 2);
    vm.warp(block.timestamp + elapsed);
  }

  function _depositInto(IERC4626 vault, uint256 amount) internal {
    deal(address(GHO), address(this), amount);
    GHO.approve(address(vault), amount);
    vault.deposit(amount, COLLECTOR);
  }
}
