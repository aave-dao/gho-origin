// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestSGhoBase.t.sol';

contract TestSGhoInitialization is TestSGhoBase {
  function test_constructor() external view {
    assertEq(sgho.GHO(), address(gho), 'GHO address mismatch');
    assertEq(sgho.DOMAIN_SEPARATOR(), DOMAIN_SEPARATOR_sGho, 'Domain separator mismatch');
  }

  function test_metadata() external view {
    assertEq(sgho.name(), 'sGho', 'Name mismatch');
    assertEq(sgho.symbol(), 'sGho', 'Symbol mismatch');
    assertEq(sgho.decimals(), 18, 'Decimals mismatch');
  }

  function test_storageSlot_verification() external pure {
    // Calculate the expected storage slot value
    // keccak256(abi.encode(uint256(keccak256("gho.storage.sGho")) - 1)) & ~bytes32(uint256(0xff))

    // Step 1: Calculate keccak256("gho.storage.sGho")
    bytes32 firstHash = keccak256(abi.encodePacked('gho.storage.sGho'));

    // Step 2: Convert to uint256 and subtract 1
    uint256 firstHashUint = uint256(firstHash);
    uint256 subtractedValue = firstHashUint - 1;

    // Step 3: Encode as uint256
    bytes memory encoded = abi.encode(subtractedValue);

    // Step 4: Calculate keccak256 of the encoded value
    bytes32 secondHash = keccak256(encoded);

    // Step 5: Apply the mask: & ~bytes32(uint256(0xff))
    bytes32 mask = ~bytes32(uint256(0xff));
    bytes32 expectedStorageSlot = secondHash & mask;

    // The expected value should be: 0x52190d4bcaca04cac5a7c2ae78ea3854d285be3b91819fb1b3ed9862d9a9a400
    bytes32 expectedValue = 0x52190d4bcaca04cac5a7c2ae78ea3854d285be3b91819fb1b3ed9862d9a9a400;

    assertEq(expectedStorageSlot, expectedValue, 'Storage slot calculation is incorrect');

    // Note: We can't directly access the private constant sGhoStorageLocation from the contract
    // but we can verify that our calculation matches the expected value
    // The storage slot calculation remains the same even though the storage layout has changed
  }

  function test_4626_initialState() external view {
    assertEq(sgho.asset(), address(gho), 'Asset mismatch');
    assertEq(sgho.totalAssets(), 0, 'Initial totalAssets mismatch');
    assertEq(sgho.totalSupply(), 0, 'Initial totalSupply mismatch');
    assertEq(sgho.decimals(), gho.decimals(), 'Decimals mismatch'); // Inherits ERC20 decimals
  }

  function test_initialization() external {
    // Deploy a new sGho instance
    address impl = address(new sGho());
    sGho newSgho = sGho(
      address(
        new TransparentUpgradeableProxy(
          impl,
          address(this),
          abi.encodeWithSelector(
            sGho.initialize.selector,
            address(gho),
            SUPPLY_CAP,
            address(this) // executor
          )
        )
      )
    );

    // Should work after initialization
    assertEq(newSgho.totalAssets(), 0, 'Should be initialized');
  }

  function test_revert_initialize_twice() external {
    // Deploy a new sGho instance
    address impl = address(new sGho());
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
      impl,
      address(this),
      abi.encodeWithSelector(
        sGho.initialize.selector,
        address(gho),
        SUPPLY_CAP,
        address(this) // executor
      )
    );

    sGho newSgho = sGho(address(proxy));

    // Should revert on second initialization via proxy
    vm.expectRevert();
    newSgho.initialize(address(gho), SUPPLY_CAP, address(this));
  }

  // ========================================
  // GETTER FUNCTIONS & STATE ACCESS TESTS
  // ========================================

  function test_getter_GHO() external view {
    assertEq(sgho.GHO(), address(gho), 'GHO address getter should return correct address');
  }

  function test_getter_name() external view {
    assertEq(sgho.name(), 'sGho', 'Name should be sGho');
  }

  function test_getter_symbol() external view {
    assertEq(sgho.symbol(), 'sGho', 'Symbol should be sGho');
  }

  function test_getter_decimals() external view {
    assertEq(sgho.decimals(), 18, 'Decimals should be 18');
  }

  function test_getter_asset() external view {
    assertEq(sgho.asset(), address(gho), 'Asset should return GHO address');
  }

  function test_getter_targetRate() external view {
    assertEq(sgho.targetRate(), 1000, 'Target rate should be 10% (1000 bps)');
  }

  function test_getter_MAX_SAFE_RATE() external view {
    assertEq(sgho.MAX_SAFE_RATE(), 5000, 'Max target rate should match constant');
  }

  function test_getter_supplyCap() external view {
    assertEq(sgho.supplyCap(), SUPPLY_CAP, 'Supply cap should match constant');
  }

  function test_getter_yieldIndex() external view {
    assertEq(sgho.yieldIndex(), 1e27, 'Initial yield index should be RAY (1e27)');
  }

  function test_getter_lastUpdate() external view {
    assertEq(sgho.lastUpdate(), block.timestamp, 'Last update should be current timestamp');
  }

  function test_getter_PAUSE_GUARDIAN_ROLE() external view {
    assertEq(
      sgho.PAUSE_GUARDIAN_ROLE(),
      keccak256('PAUSE_GUARDIAN_ROLE'),
      'PAUSE_GUARDIAN_ROLE should match hash'
    );
  }

  function test_getter_TOKEN_RESCUER_ROLE() external view {
    assertEq(
      sgho.TOKEN_RESCUER_ROLE(),
      keccak256('TOKEN_RESCUER_ROLE'),
      'TOKEN_RESCUER_ROLE should match hash'
    );
  }

  function test_getter_YIELD_MANAGER_ROLE() external view {
    assertEq(
      sgho.YIELD_MANAGER_ROLE(),
      keccak256('YIELD_MANAGER_ROLE'),
      'YIELD_MANAGER_ROLE should match hash'
    );
  }

  function test_getter_DOMAIN_SEPARATOR() external view {
    assertEq(
      sgho.DOMAIN_SEPARATOR(),
      DOMAIN_SEPARATOR_sGho,
      'Domain separator should match calculated value'
    );
  }

  function test_getter_totalSupply() external view {
    assertEq(sgho.totalSupply(), 0, 'Initial total supply should be 0');
  }

  function test_getter_balanceOf() external {
    vm.startPrank(user1);
    uint256 depositAmount = 100 ether;
    sgho.deposit(depositAmount, user1);
    assertEq(sgho.balanceOf(user1), depositAmount, 'Balance should match deposited amount');
    assertEq(sgho.balanceOf(user2), 0, 'User2 balance should be 0');
    vm.stopPrank();
  }

  function test_getter_totalAssets() external view {
    assertEq(sgho.totalAssets(), 0, 'Initial total assets should be 0');
  }

  function test_getter_ratePerSecond() external view {
    uint256 targetRate = sgho.targetRate();
    uint256 annualRateRay = (targetRate * RAY) / 10000;
    uint256 ratePerSecond = (annualRateRay * RAY) / 365 days;
    uint256 expectedRatePerSecond = ratePerSecond / RAY;
    assertEq(
      sgho.ratePerSecond(),
      expectedRatePerSecond,
      'Rate per second should match calculated value'
    );
  }
}
