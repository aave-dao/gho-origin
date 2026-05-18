// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Collector} from 'aave-v3-origin/contracts/treasury/Collector.sol';

contract MockCollector is Collector {
  constructor() Collector() {}
}
