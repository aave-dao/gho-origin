// SPDX-License-Identifier: agpl-3

pragma solidity ^0.8.19;

import {stdStorage, StdStorage} from 'forge-std/Test.sol';
import {TestnetProcedures, TestnetERC20} from 'lib/aave-v3-origin/tests/utils/TestnetProcedures.sol';
import {IAccessControl} from 'openzeppelin-contracts/contracts/access/IAccessControl.sol';
import {AccessControlUpgradeable} from 'openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol';
import {ECDSA} from 'openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol';
import {ERC20PermitUpgradeable} from 'openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol';
import {ERC4626} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol';
import {IERC4626} from 'openzeppelin-contracts/contracts/interfaces/IERC4626.sol';
import {IERC20Errors} from 'openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol';
import {IERC20Metadata as IERC20} from 'openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {Math} from 'openzeppelin-contracts/contracts/utils/math/Math.sol';
import {TransparentUpgradeableProxy} from 'openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';
import {PausableUpgradeable} from 'openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol';

import {IsGho} from '../../src/contracts/sgho/interfaces/IsGho.sol';
import {sGho} from '../../src/contracts/sgho/sGho.sol';

contract TestSGhoBase is TestnetProcedures {
  using stdStorage for StdStorage;
  using Math for uint256;

  // Constants for yield calculations (using ray precision - 27 decimals)
  uint256 internal constant RAY = 1e27;

  // Contracts
  sGho internal sgho;
  TestnetERC20 internal gho;

  // Users & Keys
  address internal user1;
  uint256 internal user1PrivateKey;
  address internal user2;
  address internal Admin;
  address internal yManager; // Yield manager user
  address internal fundsAdmin; // Funds admin user

  uint16 internal constant MAX_SAFE_RATE = 50_00; // 50%
  uint160 internal constant SUPPLY_CAP = 1_000_000 ether; // 1M GHO

  // Permit constants
  string internal constant VERSION = '1'; // Matches sGho constructor
  bytes32 internal DOMAIN_SEPARATOR_sGho;

  function setUp() public virtual {
    initTestEnvironment(false); // Use TestnetProcedures setup

    // Users
    (user1, user1PrivateKey) = makeAddrAndKey('user1');
    user2 = makeAddr('0xCAFE');
    Admin = makeAddr('0x1234'); // proxy admin address
    yManager = makeAddr('0xDEAD'); // Yield manager address
    fundsAdmin = makeAddr('0xA11D'); // Funds admin address

    // Deploy Mocks & sGho
    gho = new TestnetERC20('Mock GHO', 'GHO', 18, poolAdmin);

    // Deploy sGho implementation and proxy
    address sghoImpl = address(new sGho());
    sgho = sGho(
      address(
        new TransparentUpgradeableProxy(
          sghoImpl,
          Admin,
          abi.encodeWithSelector(
            sGho.initialize.selector,
            address(gho),
            SUPPLY_CAP,
            address(this) // executor
          )
        )
      )
    );

    sgho.grantRole(sgho.YIELD_MANAGER_ROLE(), yManager);
    sgho.grantRole(sgho.TOKEN_RESCUER_ROLE(), fundsAdmin);

    deal(address(user1), 10 ether);
    deal(address(gho), address(sgho), 1 ether, true);

    // Set target rate as yield manager
    vm.startPrank(yManager);
    sgho.setTargetRate(1000); // 10% APR
    vm.stopPrank();

    // Calculate domain separator for permits
    DOMAIN_SEPARATOR_sGho = sgho.DOMAIN_SEPARATOR();

    // Initial GHO funding for users
    deal(address(gho), user1, 1_000_000 ether, true);
    deal(address(gho), user2, 1_000_000 ether, true);

    // Approve sGho to spend user GHO
    vm.startPrank(user1);
    gho.approve(address(sgho), type(uint256).max);
    vm.stopPrank();
    vm.startPrank(user2);
    gho.approve(address(sgho), type(uint256).max);
    vm.stopPrank();
  }

  // ========================================
  // INTERNAL UTILITY FUNCTIONS
  // ========================================

  /// @dev Emulates the yieldIndex calculation as in sGho._getCurrentYieldIndex(), using OpenZeppelin Math for all operations
  function _emulateYieldIndex(
    uint256 prevYieldIndex,
    uint16 targetRate,
    uint256 timeSinceLastUpdate
  ) internal pure returns (uint256) {
    if (targetRate == 0 || timeSinceLastUpdate == 0) return prevYieldIndex;

    // Convert targetRate from basis points to ray
    uint256 annualRateRay = (uint256(targetRate) * RAY) / 10000;
    // Calculate the rate per second (new contract logic)
    uint256 ratePerSecondRay = (annualRateRay * RAY) / 365 days;
    uint256 ratePerSecondNormalized = ratePerSecondRay / RAY;
    // Calculate accumulated rate and growth factor
    uint256 accumulatedRate = ratePerSecondNormalized * timeSinceLastUpdate;
    uint256 growthFactor = RAY + accumulatedRate;
    return (prevYieldIndex * growthFactor) / RAY;
  }

  function _createPermitSignature(
    address owner,
    address spender,
    uint256 value,
    uint256 nonce,
    uint256 deadline,
    uint256 privateKey
  ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
    bytes32 structHash = vm.eip712HashStruct(
      'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)',
      abi.encode(owner, spender, value, nonce, deadline)
    );

    bytes32 hash = keccak256(abi.encodePacked('\x19\x01', sgho.DOMAIN_SEPARATOR(), structHash));
    return vm.sign(privateKey, hash);
  }

  function _wadPow(uint256 base, uint256 exp) internal pure returns (uint256) {
    uint256 res = 1e18; // WAD
    while (exp > 0) {
      if (exp % 2 == 1) {
        res = (res * base) / 1e18;
      }
      base = (base * base) / 1e18;
      exp /= 2;
    }
    return res;
  }
}
