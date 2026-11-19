// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {SwapToGHOTest, SwapFromGHOTest, SwapToSGhoTest, SwapFromSGhoTest, SwapSlippageTest} from './TestGhoRouterSwap.t.sol';
import {PreviewSwapsTest, PreviewMatchesSwapTest} from './TestGhoRouterPreviewSwap.t.sol';

/**
 * @title GhoRouterTest
 * @notice Re-runs GhoRouter swap and preview tests with asymmetric GSM fees and with no fee strategy
 * @dev Run with: forge test --match-path test/unit/GhoRouter/TestGhoRouterFeeVariants.t.sol -vvv
 */
contract SwapToGHOAsymmetricFeesTest is SwapToGHOTest {
  function setUp() public override {
    super.setUp();
    _setGsmFees(0.05e4, 0.2e4);
  }
}

contract SwapToGHONoFeesTest is SwapToGHOTest {
  function setUp() public override {
    super.setUp();
    _setGsmFees(0, 0);
  }
}

contract SwapFromGHOAsymmetricFeesTest is SwapFromGHOTest {
  function setUp() public override {
    super.setUp();
    _setGsmFees(0.05e4, 0.2e4);
  }
}

contract SwapFromGHONoFeesTest is SwapFromGHOTest {
  function setUp() public override {
    super.setUp();
    _setGsmFees(0, 0);
  }
}

contract SwapToSGhoAsymmetricFeesTest is SwapToSGhoTest {
  function setUp() public override {
    super.setUp();
    _setGsmFees(0.05e4, 0.2e4);
  }
}

contract SwapToSGhoNoFeesTest is SwapToSGhoTest {
  function setUp() public override {
    super.setUp();
    _setGsmFees(0, 0);
  }
}

contract SwapFromSGhoAsymmetricFeesTest is SwapFromSGhoTest {
  function setUp() public override {
    super.setUp();
    _setGsmFees(0.05e4, 0.2e4);
  }
}

contract SwapFromSGhoNoFeesTest is SwapFromSGhoTest {
  function setUp() public override {
    super.setUp();
    _setGsmFees(0, 0);
  }
}

contract SwapSlippageAsymmetricFeesTest is SwapSlippageTest {
  function setUp() public override {
    super.setUp();
    _setGsmFees(0.05e4, 0.2e4);
  }
}

contract SwapSlippageNoFeesTest is SwapSlippageTest {
  function setUp() public override {
    super.setUp();
    _setGsmFees(0, 0);
  }
}

contract PreviewSwapsAsymmetricFeesTest is PreviewSwapsTest {
  function setUp() public override {
    super.setUp();
    _setGsmFees(0.05e4, 0.2e4);
  }
}

contract PreviewSwapsNoFeesTest is PreviewSwapsTest {
  function setUp() public override {
    super.setUp();
    _setGsmFees(0, 0);
  }
}

contract PreviewMatchesSwapAsymmetricFeesTest is PreviewMatchesSwapTest {
  function setUp() public override {
    super.setUp();
    _setGsmFees(0.05e4, 0.2e4);
  }
}

contract PreviewMatchesSwapNoFeesTest is PreviewMatchesSwapTest {
  function setUp() public override {
    super.setUp();
    _setGsmFees(0, 0);
  }
}
