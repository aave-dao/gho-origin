// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from 'forge-std/Test.sol';
import {IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {IERC4626} from 'openzeppelin-contracts/contracts/interfaces/IERC4626.sol';
import {IAccessControl} from 'openzeppelin-contracts/contracts/access/IAccessControl.sol';
import {SafeCast} from 'openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {TransparentUpgradeableProxy} from 'openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {ICollector} from 'aave-v3-origin/contracts/treasury/ICollector.sol';
import {WadRayMath} from 'aave-v3-origin/contracts/protocol/libraries/math/WadRayMath.sol';

import {sGho} from 'src/contracts/sgho/sGho.sol';
import {sGhoInstance} from 'src/contracts/sgho/instances/sGhoInstance.sol';
import {sGhoSteward, IsGhoSteward} from 'src/contracts/misc/sGhoSteward.sol';

/// @dev Funds an sGHO deployment through the steward from the live mainnet collector. The live
/// collector and pools use opcodes newer than the repo's `paris` target.
/// forge-config: default.evm_version = "cancun"
/// forge-config: ci.evm_version = "cancun"
contract sGhoStewardFundingForkTest is Test {
  using SafeCast for uint256;

  address internal constant GHO = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f;
  address internal constant COLLECTOR = 0x464C71f6c2F760DdA6093dCB91C24c39e5d6e18c;
  address internal constant EXECUTOR = 0x5300A1a15135EA4dc7aD5a167152C01EFc9b192A; // collector admin
  address internal constant A_ETH_GHO = 0x00907f9921424583e7ffBfEdf84F92B7B2Be4977;
  address internal constant A_ETH_LIDO_GHO = 0x18eFE565A5373f430e2F809b97De30335B3ad96A;
  address internal constant STATA_ETH_LIDO_GHO = 0xC71Ea051a5F82c67ADcF634c36FFE6334793D24C;

  uint256 internal constant FORK_BLOCK = 26505980;
  uint256 internal constant DEPOSIT = 1_000_000 ether;
  uint256 internal constant FUNDING = 1_000 ether;

  address internal riskCouncil = makeAddr('riskCouncil');
  sGho internal sgho;
  sGhoSteward internal steward;
  bool internal forked;

  function setUp() external {
    string memory rpc = vm.envOr('RPC_MAINNET', string(''));
    if (bytes(rpc).length == 0) return;
    vm.createSelectFork(rpc, FORK_BLOCK);
    forked = true;

    sgho = sGho(
      address(
        new TransparentUpgradeableProxy(
          address(new sGhoInstance()),
          makeAddr('proxyAdmin'),
          abi.encodeCall(
            sGhoInstance.initialize,
            (
              GHO,
              type(uint40).max,
              address(this),
              WadRayMath.RAY.toUint120(),
              block.timestamp.toUint40(),
              10_00
            )
          )
        )
      )
    );
    steward = new sGhoSteward({
      owner: EXECUTOR,
      riskCouncil: riskCouncil,
      sGho: address(sgho),
      collector: COLLECTOR,
      maxFundingAmount: 100_000 ether,
      fundingBufferDuration: 90 days
    });

    bytes32 fundsAdminRole = ICollector(COLLECTOR).FUNDS_ADMIN_ROLE();
    vm.prank(EXECUTOR);
    IAccessControl(COLLECTOR).grantRole(fundsAdminRole, address(steward));

    // A depositor, so sGHO owes more GHO than it holds once yield accrues
    address depositor = makeAddr('depositor');
    deal(GHO, depositor, DEPOSIT);
    vm.startPrank(depositor);
    IERC20(GHO).approve(address(sgho), DEPOSIT);
    sgho.deposit(DEPOSIT, depositor);
    vm.stopPrank();

    vm.warp(block.timestamp + 30 days);
  }

  modifier onlyForked() {
    vm.skip(!forked);
    _;
  }

  function test_fork_fundSGho() external onlyForked {
    _assertFunds(GHO);
  }

  function test_fork_fundSGhoFromAToken_core() external onlyForked {
    _assertFunds(A_ETH_GHO);
  }

  function test_fork_fundSGhoFromAToken_prime() external onlyForked {
    _assertFunds(A_ETH_LIDO_GHO);
  }

  function test_fork_fundSGhoFromVault_primeStaticAToken() external onlyForked {
    uint256 shares = IERC4626(STATA_ETH_LIDO_GHO).previewWithdraw(FUNDING) + 1;
    deal(STATA_ETH_LIDO_GHO, COLLECTOR, shares);

    _assertFunds(STATA_ETH_LIDO_GHO);
  }

  function test_fork_revert_fundSGhoFromAToken_otherPoolAToken() external onlyForked {
    // The static aToken reports the Prime pool, whose GHO aToken is aEthLidoGHO
    vm.expectRevert(IsGhoSteward.InvalidFundingSource.selector);
    vm.prank(riskCouncil);
    steward.fundSGhoFromAToken(STATA_ETH_LIDO_GHO, FUNDING);
  }

  /// @dev sGHO receives exactly `FUNDING`, the collector pays for it and the steward keeps nothing
  function _assertFunds(address source) internal {
    uint256 sGhoBefore = IERC20(GHO).balanceOf(address(sgho));
    uint256 collectorBefore = IERC20(source).balanceOf(COLLECTOR);

    vm.expectEmit(address(steward));
    emit IsGhoSteward.SGhoFunded(riskCouncil, source, FUNDING);
    vm.prank(riskCouncil);
    if (source == GHO) {
      steward.fundSGho(FUNDING);
    } else if (source == A_ETH_GHO || source == A_ETH_LIDO_GHO) {
      steward.fundSGhoFromAToken(source, FUNDING);
    } else {
      steward.fundSGhoFromVault(source, FUNDING);
    }

    assertEq(IERC20(GHO).balanceOf(address(sgho)) - sGhoBefore, FUNDING, 'sGHO GHO');
    assertGt(collectorBefore, IERC20(source).balanceOf(COLLECTOR), 'collector paid');
    assertEq(IERC20(GHO).balanceOf(address(steward)), 0, 'steward GHO');
    assertEq(IERC20(source).balanceOf(address(steward)), 0, 'steward source');
  }
}
