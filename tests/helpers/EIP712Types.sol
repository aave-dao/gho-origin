// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

library EIP712Types {
  //BuyAssetWithSig(address originator,uint256 minAmount,address receiver,uint256 nonce,uint256 deadline)
  struct BuyAssetWithSig {
    address originator;
    uint256 minAmount;
    address receiver;
    uint256 nonce;
    uint256 deadline;
  }

  //SellAssetWithSig(address originator,uint256 maxAmount,address receiver,uint256 nonce,uint256 deadline)
  struct SellAssetWithSig {
    address originator;
    uint256 maxAmount;
    address receiver;
    uint256 nonce;
    uint256 deadline;
  }
}
