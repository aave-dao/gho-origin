// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestGhoBase.t.sol';

contract TestGsmFixedFeeStrategyFactory is TestGhoBase {
  FixedFeeStrategyFactory internal factory;

  function setUp() public {
    factory = _deployFactory(new address[](0));
  }

  function testRevision() public view {
    assertEq(factory.REVISION(), 1, 'Unexpected revision');
  }

  function testInitializeEmpty() public view {
    address[] memory strategies = factory.getFixedFeeStrategies();
    assertEq(strategies.length, 0, 'Unexpected non-empty strategies');
  }

  function testInitializeWithStrategies() public {
    FixedFeeStrategy strategyA = new FixedFeeStrategy(DEFAULT_GSM_BUY_FEE, DEFAULT_GSM_SELL_FEE);
    FixedFeeStrategy strategyB = new FixedFeeStrategy(0, DEFAULT_GSM_SELL_FEE);

    address[] memory preDeployed = new address[](2);
    preDeployed[0] = address(strategyA);
    preDeployed[1] = address(strategyB);

    address proxyAdmin = makeAddr('PROXY_ADMIN');
    FixedFeeStrategyFactory factoryImpl = new FixedFeeStrategyFactory();

    vm.expectEmit(true, true, true, true);
    emit IFixedFeeStrategyFactory.FeeStrategyCreated(
      address(strategyA),
      DEFAULT_GSM_BUY_FEE,
      DEFAULT_GSM_SELL_FEE
    );
    vm.expectEmit(true, true, true, true);
    emit IFixedFeeStrategyFactory.FeeStrategyCreated(address(strategyB), 0, DEFAULT_GSM_SELL_FEE);

    TransparentUpgradeableProxy factoryProxy = new TransparentUpgradeableProxy(
      address(factoryImpl),
      proxyAdmin,
      abi.encodeWithSignature('initialize(address[])', preDeployed)
    );
    FixedFeeStrategyFactory initialized = FixedFeeStrategyFactory(address(factoryProxy));

    address[] memory strategies = initialized.getFixedFeeStrategies();
    assertEq(strategies.length, 2, 'Unexpected strategies length');
    assertEq(strategies[0], address(strategyA), 'Unexpected first strategy');
    assertEq(strategies[1], address(strategyB), 'Unexpected second strategy');

    assertEq(
      initialized.getFixedFeeStrategy(DEFAULT_GSM_BUY_FEE, DEFAULT_GSM_SELL_FEE),
      address(strategyA),
      'Unexpected lookup for strategyA'
    );
    assertEq(
      initialized.getFixedFeeStrategy(0, DEFAULT_GSM_SELL_FEE),
      address(strategyB),
      'Unexpected lookup for strategyB'
    );
  }

  function testRevertInitializeTwice() public {
    address[] memory emptyList = new address[](0);
    vm.expectRevert('Contract instance has already been initialized');
    factory.initialize(emptyList);
  }

  function testCreateStrategies() public {
    uint256[] memory buyFees = new uint256[](1);
    uint256[] memory sellFees = new uint256[](1);
    buyFees[0] = DEFAULT_GSM_BUY_FEE;
    sellFees[0] = DEFAULT_GSM_SELL_FEE;

    address expected = vm.computeCreateAddress(address(factory), vm.getNonce(address(factory)));
    vm.expectEmit(true, true, true, true, address(factory));
    emit IFixedFeeStrategyFactory.FeeStrategyCreated(
      expected,
      DEFAULT_GSM_BUY_FEE,
      DEFAULT_GSM_SELL_FEE
    );
    address[] memory strategies = factory.createStrategies(buyFees, sellFees);

    assertEq(strategies.length, 1, 'Unexpected strategies length');
    assertEq(strategies[0], expected, 'Unexpected strategy address');
    assertEq(
      FixedFeeStrategy(strategies[0]).getBuyFee(1e4),
      DEFAULT_GSM_BUY_FEE,
      'Unexpected buy fee'
    );
    assertEq(
      FixedFeeStrategy(strategies[0]).getSellFee(1e4),
      DEFAULT_GSM_SELL_FEE,
      'Unexpected sell fee'
    );

    address[] memory tracked = factory.getFixedFeeStrategies();
    assertEq(tracked.length, 1, 'Unexpected tracked length');
    assertEq(tracked[0], strategies[0], 'Unexpected tracked strategy');
    assertEq(
      factory.getFixedFeeStrategy(DEFAULT_GSM_BUY_FEE, DEFAULT_GSM_SELL_FEE),
      strategies[0],
      'Unexpected lookup'
    );
  }

  function testCreateStrategiesMultiple() public {
    uint256[] memory buyFees = new uint256[](3);
    uint256[] memory sellFees = new uint256[](3);
    buyFees[0] = DEFAULT_GSM_BUY_FEE;
    sellFees[0] = DEFAULT_GSM_SELL_FEE;
    buyFees[1] = 0;
    sellFees[1] = DEFAULT_GSM_SELL_FEE;
    buyFees[2] = DEFAULT_GSM_BUY_FEE;
    sellFees[2] = 0;

    address[] memory strategies = factory.createStrategies(buyFees, sellFees);

    assertEq(strategies.length, 3, 'Unexpected strategies length');
    assertTrue(strategies[0] != address(0), 'Unexpected zero strategy[0]');
    assertTrue(strategies[1] != address(0), 'Unexpected zero strategy[1]');
    assertTrue(strategies[2] != address(0), 'Unexpected zero strategy[2]');
    assertTrue(strategies[0] != strategies[1], 'Unexpected duplicate strategy[0,1]');
    assertTrue(strategies[1] != strategies[2], 'Unexpected duplicate strategy[1,2]');
    assertTrue(strategies[0] != strategies[2], 'Unexpected duplicate strategy[0,2]');

    address[] memory tracked = factory.getFixedFeeStrategies();
    assertEq(tracked.length, 3, 'Unexpected tracked length');
  }

  function testCreateStrategiesReusesCached() public {
    uint256[] memory buyFees = new uint256[](1);
    uint256[] memory sellFees = new uint256[](1);
    buyFees[0] = DEFAULT_GSM_BUY_FEE;
    sellFees[0] = DEFAULT_GSM_SELL_FEE;

    address[] memory first = factory.createStrategies(buyFees, sellFees);

    vm.recordLogs();
    address[] memory second = factory.createStrategies(buyFees, sellFees);
    Vm.Log[] memory emitted = vm.getRecordedLogs();

    bytes32 createdTopic = IFixedFeeStrategyFactory.FeeStrategyCreated.selector;
    for (uint256 i = 0; i < emitted.length; i++) {
      assertTrue(
        emitted[i].topics[0] != createdTopic,
        'Unexpected FeeStrategyCreated on cache hit'
      );
    }

    assertEq(second.length, 1, 'Unexpected strategies length');
    assertEq(second[0], first[0], 'Cached strategy not reused');
    assertEq(factory.getFixedFeeStrategies().length, 1, 'Unexpected duplicate tracked');
  }

  function testRevertCreateStrategiesInvalidFeeList() public {
    uint256[] memory buyFees = new uint256[](2);
    uint256[] memory sellFees = new uint256[](1);
    buyFees[0] = DEFAULT_GSM_BUY_FEE;
    buyFees[1] = 0;
    sellFees[0] = DEFAULT_GSM_SELL_FEE;

    vm.expectRevert('INVALID_FEE_LIST');
    factory.createStrategies(buyFees, sellFees);
  }

  function testGetFixedFeeStrategyZeroForUnknown() public view {
    assertEq(
      factory.getFixedFeeStrategy(DEFAULT_GSM_BUY_FEE, DEFAULT_GSM_SELL_FEE),
      address(0),
      'Unexpected non-zero lookup'
    );
  }

  function _deployFactory(address[] memory preDeployed) internal returns (FixedFeeStrategyFactory) {
    address proxyAdmin = makeAddr('PROXY_ADMIN');
    FixedFeeStrategyFactory factoryImpl = new FixedFeeStrategyFactory();
    TransparentUpgradeableProxy factoryProxy = new TransparentUpgradeableProxy(
      address(factoryImpl),
      proxyAdmin,
      abi.encodeWithSignature('initialize(address[])', preDeployed)
    );
    return FixedFeeStrategyFactory(address(factoryProxy));
  }
}
