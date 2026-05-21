// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.19;

import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {TransparentUpgradeableProxy} from 'openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {Collector} from 'aave-v3-origin/contracts/treasury/Collector.sol';
import {ICollector} from 'aave-v3-origin/contracts/treasury/ICollector.sol';
import {IPoolAddressesProvider} from 'aave-v3-origin/contracts/interfaces/IPoolAddressesProvider.sol';

import {AccessControl} from 'src/contracts/dependencies/openzeppelin-contracts/contracts/access/AccessControl.sol';
import {Strings} from 'src/contracts/dependencies/openzeppelin-contracts/contracts/utils/Strings.sol';

import {sGho, IsGho} from 'src/contracts/sgho/sGho.sol';
import {sGhoSteward, IsGhoSteward} from 'src/contracts/misc/sGhoSteward.sol';
import {MockPool} from '../mocks/MockPool.sol';
import {MockAToken} from '../mocks/MockAToken.sol';
import {TestSGhoBase} from '../unit/TestSGhoBase.t.sol';

contract sGhoStewardTest is TestSGhoBase {
  sGhoSteward public steward;

  address public riskCouncil = makeAddr('riskCouncil');
  address public governance = makeAddr('governance');
  Collector public collector;
  MockPool public pool;
  MockAToken public primeGho;

  bytes32 public constant YIELD_MANAGER_ROLE = 'YIELD_MANAGER';

  bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

  bytes32 public constant AMPLIFICATION_MANAGER_ROLE = keccak256('AMPLIFICATION_MANAGER_ROLE');
  bytes32 public constant FLOAT_RATE_MANAGER_ROLE = keccak256('FLOAT_RATE_MANAGER_ROLE');
  bytes32 public constant FIXED_RATE_MANAGER_ROLE = keccak256('FIXED_RATE_MANAGER_ROLE');
  bytes32 public constant SUPPLY_CAP_MANAGER_ROLE = keccak256('SUPPLY_CAP_MANAGER_ROLE');
  bytes32 public constant SGHO_FUNDING_ROLE = keccak256('SGHO_FUNDING_ROLE');

  function setUp() public override {
    super.setUp();

    address collectorImpl = address(new Collector());
    collector = Collector(
      payable(
        new TransparentUpgradeableProxy(
          collectorImpl,
          Admin,
          abi.encodeWithSignature(
            'initialize(uint256,address)',
            0,
            address(this) // executor
          )
        )
      )
    );

    pool = new MockPool(IPoolAddressesProvider(address(0)));
    primeGho = new MockAToken('Mock aEthLidoGHO', 'aEthLidoGHO', 18, poolAdmin, address(pool));

    steward = new sGhoSteward(
      governance,
      riskCouncil,
      address(sgho),
      address(primeGho),
      address(collector),
      address(pool)
    );
    sgho.grantRole(sgho.YIELD_MANAGER_ROLE(), address(steward));

    // Warp past MINIMUM_DELAY so the debounce check in fundSGho does not block first-time calls.
    // block.timestamp on tests starts as 0
    vm.warp(block.timestamp + steward.MINIMUM_DELAY());
  }

  function test_wrongSetUp() public {
    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.ZeroAddress.selector));
    new sGhoSteward(
      address(0),
      riskCouncil,
      address(sgho),
      address(primeGho),
      address(collector),
      address(pool)
    );

    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.ZeroAddress.selector));
    new sGhoSteward(
      governance,
      address(0),
      address(sgho),
      address(primeGho),
      address(collector),
      address(pool)
    );

    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.ZeroAddress.selector));
    new sGhoSteward(
      governance,
      riskCouncil,
      address(0),
      address(primeGho),
      address(collector),
      address(pool)
    );

    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.ZeroAddress.selector));
    new sGhoSteward(
      governance,
      riskCouncil,
      address(sgho),
      address(0),
      address(collector),
      address(pool)
    );

    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.ZeroAddress.selector));
    new sGhoSteward(
      governance,
      riskCouncil,
      address(sgho),
      address(primeGho),
      address(0),
      address(pool)
    );

    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.ZeroAddress.selector));
    new sGhoSteward(
      governance,
      riskCouncil,
      address(sgho),
      address(primeGho),
      address(collector),
      address(0)
    );
  }

  function test_initial() public view {
    assertTrue(steward.hasRole(DEFAULT_ADMIN_ROLE, governance));
    assertFalse(steward.hasRole(DEFAULT_ADMIN_ROLE, riskCouncil));

    assertTrue(steward.hasRole(AMPLIFICATION_MANAGER_ROLE, riskCouncil));
    assertTrue(steward.hasRole(FLOAT_RATE_MANAGER_ROLE, riskCouncil));
    assertTrue(steward.hasRole(FIXED_RATE_MANAGER_ROLE, riskCouncil));
    assertTrue(steward.hasRole(SUPPLY_CAP_MANAGER_ROLE, riskCouncil));
    assertTrue(steward.hasRole(SGHO_FUNDING_ROLE, riskCouncil));

    assertFalse(steward.hasRole(AMPLIFICATION_MANAGER_ROLE, governance));
    assertFalse(steward.hasRole(FLOAT_RATE_MANAGER_ROLE, governance));
    assertFalse(steward.hasRole(FIXED_RATE_MANAGER_ROLE, governance));
    assertFalse(steward.hasRole(SUPPLY_CAP_MANAGER_ROLE, governance));
    assertFalse(steward.hasRole(SGHO_FUNDING_ROLE, governance));

    assertEq(address(steward.sGHO()), address(sgho));
  }

  function test_riskCouncilCannotGrantRoles() public {
    address user = makeAddr('user');

    vm.expectRevert(_craftError(riskCouncil, DEFAULT_ADMIN_ROLE));
    vm.prank(riskCouncil);
    AccessControl(steward).grantRole(AMPLIFICATION_MANAGER_ROLE, user);

    vm.expectRevert(_craftError(riskCouncil, DEFAULT_ADMIN_ROLE));
    vm.prank(riskCouncil);
    AccessControl(steward).grantRole(FLOAT_RATE_MANAGER_ROLE, user);

    vm.expectRevert(_craftError(riskCouncil, DEFAULT_ADMIN_ROLE));
    vm.prank(riskCouncil);
    AccessControl(steward).grantRole(FIXED_RATE_MANAGER_ROLE, user);

    vm.expectRevert(_craftError(riskCouncil, DEFAULT_ADMIN_ROLE));
    vm.prank(riskCouncil);
    AccessControl(steward).grantRole(SUPPLY_CAP_MANAGER_ROLE, user);

    vm.expectRevert(_craftError(riskCouncil, DEFAULT_ADMIN_ROLE));
    vm.prank(riskCouncil);
    AccessControl(steward).grantRole(SGHO_FUNDING_ROLE, user);
  }

  function test_setRateConfig() public {
    IsGhoSteward.RateConfig memory initialConfig = steward.getRateConfig();

    assertEq(initialConfig.amplification, 0);
    assertEq(initialConfig.floatRate, 0);
    assertEq(initialConfig.fixedRate, 0);

    IsGhoSteward.RateConfig memory newConfig = IsGhoSteward.RateConfig({
      amplification: 100_00, // AMPLIFICATION_NUMERATOR
      floatRate: 200, // 2%
      fixedRate: 200 // 2%
    });

    vm.prank(riskCouncil);
    steward.setRateConfig(newConfig);

    IsGhoSteward.RateConfig memory configAfterUpdate = steward.getRateConfig();

    assertEq(configAfterUpdate.amplification, 100_00);
    assertEq(configAfterUpdate.floatRate, 200);
    assertEq(configAfterUpdate.fixedRate, 200);

    assertEq(sgho.targetRate(), 400);
  }

  function test_setRateConfigAmplificationRateOnly() public {
    IsGhoSteward.RateConfig memory initialConfig = steward.getRateConfig();

    assertEq(initialConfig.amplification, 0);
    assertEq(initialConfig.floatRate, 0);
    assertEq(initialConfig.fixedRate, 0);

    IsGhoSteward.RateConfig memory newConfig = IsGhoSteward.RateConfig({
      amplification: 100_00, // 100%
      floatRate: 2_00, // 2%
      fixedRate: 2_00 // 2%
    });

    vm.prank(riskCouncil);
    steward.setRateConfig(newConfig);

    IsGhoSteward.RateConfig memory configAfterUpdate = steward.getRateConfig();

    assertEq(configAfterUpdate.amplification, 100_00);
    assertEq(configAfterUpdate.floatRate, 2_00);
    assertEq(configAfterUpdate.fixedRate, 2_00);

    vm.startPrank(governance);

    steward.revokeRole(FIXED_RATE_MANAGER_ROLE, riskCouncil);
    steward.revokeRole(FLOAT_RATE_MANAGER_ROLE, riskCouncil);

    vm.stopPrank();

    newConfig = IsGhoSteward.RateConfig({
      amplification: 200_00, // new
      floatRate: 2_00, // default
      fixedRate: 2_00 // default
    });

    vm.prank(riskCouncil);
    steward.setRateConfig(newConfig);

    configAfterUpdate = steward.getRateConfig();

    assertEq(configAfterUpdate.amplification, 200_00);
    assertEq(configAfterUpdate.floatRate, 2_00);
    assertEq(configAfterUpdate.fixedRate, 2_00);

    assertEq(sgho.targetRate(), 6_00);

    vm.prank(governance);

    steward.revokeRole(AMPLIFICATION_MANAGER_ROLE, riskCouncil);

    newConfig = IsGhoSteward.RateConfig({
      amplification: 300_00, // new
      floatRate: 2_00, // default
      fixedRate: 2_00 // default
    });

    vm.startPrank(riskCouncil);

    vm.expectRevert(_craftError(riskCouncil, AMPLIFICATION_MANAGER_ROLE));
    steward.setRateConfig(newConfig);
  }

  function test_setRateConfigFloatRateOnly() public {
    IsGhoSteward.RateConfig memory initialConfig = steward.getRateConfig();

    assertEq(initialConfig.amplification, 0);
    assertEq(initialConfig.floatRate, 0);
    assertEq(initialConfig.fixedRate, 0);

    IsGhoSteward.RateConfig memory newConfig = IsGhoSteward.RateConfig({
      amplification: 100_00, // 100%
      floatRate: 2_00, // 2%
      fixedRate: 2_00 // 2%
    });

    vm.prank(riskCouncil);
    steward.setRateConfig(newConfig);

    IsGhoSteward.RateConfig memory configAfterUpdate = steward.getRateConfig();

    assertEq(configAfterUpdate.amplification, 100_00);
    assertEq(configAfterUpdate.floatRate, 2_00);
    assertEq(configAfterUpdate.fixedRate, 2_00);

    vm.startPrank(governance);

    steward.revokeRole(AMPLIFICATION_MANAGER_ROLE, riskCouncil);
    steward.revokeRole(FIXED_RATE_MANAGER_ROLE, riskCouncil);

    vm.stopPrank();

    newConfig = IsGhoSteward.RateConfig({
      amplification: 100_00, // default
      floatRate: 3_00, // new
      fixedRate: 2_00 // default
    });

    vm.prank(riskCouncil);
    steward.setRateConfig(newConfig);

    configAfterUpdate = steward.getRateConfig();

    assertEq(configAfterUpdate.amplification, 100_00);
    assertEq(configAfterUpdate.floatRate, 3_00);
    assertEq(configAfterUpdate.fixedRate, 2_00);

    assertEq(sgho.targetRate(), 500);

    vm.prank(governance);
    steward.revokeRole(FLOAT_RATE_MANAGER_ROLE, riskCouncil);

    newConfig = IsGhoSteward.RateConfig({
      amplification: 100_00, // default
      floatRate: 4_00, // new
      fixedRate: 2_00 // default
    });

    vm.startPrank(riskCouncil);
    vm.expectRevert(_craftError(riskCouncil, FLOAT_RATE_MANAGER_ROLE));
    steward.setRateConfig(newConfig);
  }

  function test_setRateConfigFixedRateOnly() public {
    IsGhoSteward.RateConfig memory initialConfig = steward.getRateConfig();

    assertEq(initialConfig.amplification, 0);
    assertEq(initialConfig.floatRate, 0);
    assertEq(initialConfig.fixedRate, 0);

    IsGhoSteward.RateConfig memory newConfig = IsGhoSteward.RateConfig({
      amplification: 100_00, // 100%
      floatRate: 2_00, // 2%
      fixedRate: 2_00 // 2%
    });

    vm.prank(riskCouncil);
    steward.setRateConfig(newConfig);

    IsGhoSteward.RateConfig memory configAfterUpdate = steward.getRateConfig();

    assertEq(configAfterUpdate.amplification, 100_00);
    assertEq(configAfterUpdate.floatRate, 2_00);
    assertEq(configAfterUpdate.fixedRate, 2_00);

    vm.startPrank(governance);

    steward.revokeRole(AMPLIFICATION_MANAGER_ROLE, riskCouncil);
    steward.revokeRole(FLOAT_RATE_MANAGER_ROLE, riskCouncil);

    vm.stopPrank();

    newConfig = IsGhoSteward.RateConfig({
      amplification: 100_00, // default
      floatRate: 200, // default
      fixedRate: 3_00 // new
    });

    vm.prank(riskCouncil);
    steward.setRateConfig(newConfig);

    configAfterUpdate = steward.getRateConfig();

    assertEq(configAfterUpdate.amplification, 100_00);
    assertEq(configAfterUpdate.floatRate, 200);
    assertEq(configAfterUpdate.fixedRate, 300);

    assertEq(sgho.targetRate(), 500);

    vm.prank(governance);

    steward.revokeRole(FIXED_RATE_MANAGER_ROLE, riskCouncil);

    newConfig = IsGhoSteward.RateConfig({
      amplification: 100_00, // default
      floatRate: 200, // default
      fixedRate: 4_00 // new
    });

    vm.startPrank(riskCouncil);

    vm.expectRevert(_craftError(riskCouncil, FIXED_RATE_MANAGER_ROLE));
    steward.setRateConfig(newConfig);
  }

  function test_setRateSameValue() public {
    IsGhoSteward.RateConfig memory initialConfig = steward.getRateConfig();

    assertEq(initialConfig.amplification, 0);
    assertEq(initialConfig.floatRate, 0);
    assertEq(initialConfig.fixedRate, 0);

    IsGhoSteward.RateConfig memory newConfig = IsGhoSteward.RateConfig({
      amplification: 0,
      floatRate: 0,
      fixedRate: 0
    });

    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.RateUnchanged.selector));
    vm.prank(riskCouncil);
    steward.setRateConfig(newConfig);
  }

  function test_supplyCap() public {
    uint256 initialSupplyCap = sgho.supplyCap();
    assertEq(initialSupplyCap, SUPPLY_CAP);

    vm.prank(riskCouncil);
    steward.setSupplyCap(type(uint160).max);

    uint256 supplyCapAfterUpdate = sgho.supplyCap();
    assertEq(supplyCapAfterUpdate, type(uint160).max);

    vm.prank(governance);
    steward.revokeRole(SUPPLY_CAP_MANAGER_ROLE, riskCouncil);

    vm.startPrank(riskCouncil);

    vm.expectRevert(_craftError(riskCouncil, SUPPLY_CAP_MANAGER_ROLE));
    steward.setSupplyCap(1e18);
  }

  function test_invalidSupplyCap(uint256 newSupplyCap) public {
    newSupplyCap = bound(newSupplyCap, uint256(type(uint160).max) + 1, type(uint256).max);

    uint256 initialSupplyCap = sgho.supplyCap();
    assertEq(initialSupplyCap, SUPPLY_CAP);

    vm.startPrank(riskCouncil);

    steward.setSupplyCap(type(uint160).max);

    uint256 supplyCapAfterUpdate = sgho.supplyCap();
    assertEq(supplyCapAfterUpdate, type(uint160).max);

    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.SupplyCapUnchanged.selector));
    steward.setSupplyCap(type(uint160).max);

    vm.expectRevert("SafeCast: value doesn't fit in 160 bits");
    steward.setSupplyCap(newSupplyCap);
  }

  function test_previewTargetRate(uint16 ampl, uint16 float, uint16 fix) public {
    vm.assume((uint256(ampl) * float) / 1e4 + fix < 5e3);
    vm.assume(ampl != 0 || float != 0 || fix != 0);

    vm.startPrank(riskCouncil);

    IsGhoSteward.RateConfig memory newConfig = IsGhoSteward.RateConfig({
      amplification: ampl,
      floatRate: float,
      fixedRate: fix
    });

    uint16 target = steward.previewTargetRate(newConfig);
    uint16 resultTarget = steward.setRateConfig(newConfig);

    IsGhoSteward.RateConfig memory configAfterUpdate = steward.getRateConfig();

    assertEq(configAfterUpdate.amplification, ampl);
    assertEq(configAfterUpdate.floatRate, float);
    assertEq(configAfterUpdate.fixedRate, fix);

    assertEq(sgho.targetRate(), target);
    assertEq(resultTarget, target);
  }

  function test_setRateConfigStruct(IsGhoSteward.RateConfig memory fuzzConfig) public {
    vm.assume(
      fuzzConfig.amplification != 0 || fuzzConfig.floatRate != 0 || fuzzConfig.fixedRate != 0
    );

    IsGhoSteward.RateConfig memory initialConfig = steward.getRateConfig();

    assertEq(initialConfig.amplification, 0);
    assertEq(initialConfig.floatRate, 0);
    assertEq(initialConfig.fixedRate, 0);

    vm.startPrank(riskCouncil);

    uint256 fuzzTarget = (uint256(fuzzConfig.amplification) * fuzzConfig.floatRate) /
      1e4 +
      fuzzConfig.fixedRate;

    if (fuzzTarget <= 5e3) {
      uint16 previewFuzzRate = steward.previewTargetRate(fuzzConfig);
      assertEq(previewFuzzRate, fuzzTarget);

      steward.setRateConfig(fuzzConfig);

      IsGhoSteward.RateConfig memory configAfterUpdate = steward.getRateConfig();

      assertEq(configAfterUpdate.amplification, fuzzConfig.amplification);
      assertEq(configAfterUpdate.floatRate, fuzzConfig.floatRate);
      assertEq(configAfterUpdate.fixedRate, fuzzConfig.fixedRate);

      assertEq(sgho.targetRate(), fuzzTarget);
    } else {
      vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.MaxRateExceeded.selector));
      steward.previewTargetRate(fuzzConfig);

      vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.MaxRateExceeded.selector));
      steward.setRateConfig(fuzzConfig);
    }
  }

  function test_setRateMoreThanMax(uint16 ampl, uint16 float, uint16 fix) public {
    vm.assume((uint256(ampl) * float) / 1e4 + fix > 5e3);

    vm.startPrank(riskCouncil);

    IsGhoSteward.RateConfig memory newConfig = IsGhoSteward.RateConfig({
      amplification: ampl,
      floatRate: float,
      fixedRate: fix
    });

    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.MaxRateExceeded.selector));
    steward.previewTargetRate(newConfig);

    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.MaxRateExceeded.selector));
    steward.setRateConfig(newConfig);
  }

  function test_fundSGhoNoRole() public {
    address user = makeAddr('user');
    vm.expectRevert(_craftError(user, SGHO_FUNDING_ROLE));
    vm.prank(user);
    steward.fundSGho(100_000 ether, false);
  }

  function test_fundSGhoZeroAmount() public {
    vm.expectRevert(IsGhoSteward.ZeroAmount.selector);
    vm.prank(riskCouncil);
    steward.fundSGho(0, false);
  }

  function test_fundSGhoMaxTransferExceeded() public {
    uint256 maxTransfer = steward.getMaxTransferAmount();
    vm.expectRevert(abi.encodeWithSelector(IsGhoSteward.MaxTransferExceeded.selector, maxTransfer));
    vm.prank(riskCouncil);
    steward.fundSGho(maxTransfer + 1, false);
  }

  function test_fundSGhoNoFunds() public {
    collector.grantRole(collector.FUNDS_ADMIN_ROLE(), address(steward));
    vm.expectRevert('ERC20: transfer amount exceeds balance');
    vm.prank(riskCouncil);
    steward.fundSGho(100_000 ether, false);
  }

  function test_fundSGhoNotFundsAdmin() public {
    vm.expectRevert(ICollector.OnlyFundsAdmin.selector);
    vm.prank(riskCouncil);
    steward.fundSGho(100_000 ether, false);
  }

  function test_fundSGhoDebounceNotRespected() public {
    collector.grantRole(collector.FUNDS_ADMIN_ROLE(), address(steward));
    deal(address(gho), address(collector), 200_000 ether);

    // First call succeeds and writes _transferDebounce = block.timestamp.
    vm.prank(riskCouncil);
    steward.fundSGho(100_000 ether, false);

    // Second call immediately after must revert with DebounceNotRespected.
    vm.expectRevert(IsGhoSteward.DebounceNotRespected.selector);
    vm.prank(riskCouncil);
    steward.fundSGho(100_000 ether, false);

    // Move past MINIMUM_DELAY and the next call succeeds.
    vm.warp(block.timestamp + steward.MINIMUM_DELAY());

    vm.prank(riskCouncil);
    steward.fundSGho(100_000 ether, false);
  }

  function test_fundSGho(uint256 amount) public {
    amount = bound(amount, 1, steward.getMaxTransferAmount());

    collector.grantRole(collector.FUNDS_ADMIN_ROLE(), address(steward));
    deal(address(gho), address(collector), amount);

    uint256 sghoBalanceBefore = gho.balanceOf(address(sgho));

    vm.expectEmit(true, true, true, true, address(steward));
    emit IsGhoSteward.SGhoFunded(amount);
    vm.prank(riskCouncil);
    steward.fundSGho(amount, false);

    assertEq(gho.balanceOf(address(sgho)), sghoBalanceBefore + amount);
    assertEq(gho.balanceOf(address(collector)), 0);
  }

  function test_fundSGhoWithdrawFromAave(uint256 amount) public {
    amount = bound(amount, 1, steward.getMaxTransferAmount());

    collector.grantRole(collector.FUNDS_ADMIN_ROLE(), address(steward));
    pool.setATokenAddress(address(gho), address(primeGho));

    // Collector holds primeGHO (aEthLidoGHO) that the steward will transfer to itself.
    deal(address(primeGho), address(collector), amount, true);
    // MockPool holds GHO so it can fulfill the withdraw call back to the collector.
    deal(address(gho), address(pool), amount);

    uint256 sghoBalanceBefore = gho.balanceOf(address(sgho));

    vm.expectEmit(true, true, true, true, address(steward));
    emit IsGhoSteward.SGhoFunded(amount);
    vm.prank(riskCouncil);
    steward.fundSGho(amount, true);

    assertEq(gho.balanceOf(address(sgho)), sghoBalanceBefore + amount);
    assertEq(gho.balanceOf(address(collector)), 0);
    assertEq(gho.balanceOf(address(pool)), 0);
    assertEq(primeGho.balanceOf(address(collector)), 0);
    assertEq(primeGho.balanceOf(address(steward)), 0);
  }

  function test_setMaxTransferAmountNoRole() public {
    vm.expectRevert(_craftError(riskCouncil, DEFAULT_ADMIN_ROLE));
    vm.prank(riskCouncil);
    steward.setMaxTransferAmount(1);
  }

  function test_setMaxTransferAmountUnchanged() public {
    uint256 maxTransferAmount = steward.getMaxTransferAmount();
    vm.expectRevert(IsGhoSteward.MaxTransferAmountUnchanged.selector);
    vm.prank(governance);
    steward.setMaxTransferAmount(maxTransferAmount);
  }

  function test_setMaxTransferAmount() public {
    uint256 maxTransferAmount = steward.getMaxTransferAmount();
    assertEq(steward.getMaxTransferAmount(), maxTransferAmount);

    vm.expectEmit(true, true, true, true, address(steward));
    emit IsGhoSteward.MaxTransferAmountUpdated(governance, maxTransferAmount * 2);
    vm.prank(governance);
    steward.setMaxTransferAmount(maxTransferAmount * 2);

    assertEq(steward.getMaxTransferAmount(), maxTransferAmount * 2);
  }

  function test_constants() public view {
    assertEq(steward.MINIMUM_DELAY(), 1 days);
    assertEq(steward.AMPLIFICATION_DENOMINATOR(), 100_00);
    assertEq(steward.MAX_RATE(), sgho.MAX_SAFE_RATE());
  }

  function _craftError(address account, bytes32 role) internal pure returns (bytes memory) {
    return
      bytes(
        string(
          abi.encodePacked(
            'AccessControl: account ',
            Strings.toHexString(account),
            ' is missing role ',
            Strings.toHexString(uint256(role), 32)
          )
        )
      );
  }
}
