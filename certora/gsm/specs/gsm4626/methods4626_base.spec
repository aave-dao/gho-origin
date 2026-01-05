
using FixedPriceStrategy4626Harness as _priceStrategy;
using FixedFeeStrategyHarness as _FixedFeeStrategy;
using GhoToken as _ghoToken;
using GhoReserve as _ghoReserve;

/////////////////// Methods ////////////////////////

methods
{
  function getAvailableLiquidity() external returns (uint256) envfree;
  function getCurrentBacking() external returns(uint256, uint256) envfree;

  // GSM4626.sol
  function getUsed() external returns (uint256) envfree;
  function getUnderlyingAssetUnits() external returns (uint256) envfree;

  // priceStrategy
  function _priceStrategy.getAssetPriceInGho(uint256, bool) external returns(uint256) envfree;
  function _priceStrategy.getUnderlyingAssetUnits() external returns(uint256) envfree;
  function _priceStrategy.PRICE_RATIO() external returns(uint256) envfree;

  // feeStrategy
  function _FixedFeeStrategy.getBuyFeeBP() external returns(uint256) envfree;
  function _FixedFeeStrategy.getSellFeeBP() external returns(uint256) envfree;
  function _FixedFeeStrategy.getBuyFee(uint256) external returns(uint256) envfree;
  function _FixedFeeStrategy.getSellFee(uint256) external returns(uint256) envfree;

  // GhoToken
  function _ghoToken.balanceOf(address) external returns (uint256) envfree;
  function _ghoToken.totalSupply() external returns(uint256) envfree;

  // Harness
  function getPriceRatio() external returns (uint256) envfree;
  function getAccruedFees() external returns (uint256) envfree;
}

definition harnessOnlyMethods(method f) returns bool =
        (f.selector == sig:getAccruedFees().selector ||
        f.selector == sig:getDearth().selector ||
        f.selector == sig:getPriceRatio().selector);

definition buySellAssetsFunctions(method f) returns bool =
        (f.selector == sig:buyAsset(uint256,address).selector ||
        f.selector == sig:buyAssetWithSig(address,uint256,address,uint256,bytes).selector ||
        f.selector == sig:sellAsset(uint256,address).selector ||
        f.selector == sig:sellAssetWithSig(address,uint256,address,uint256,bytes).selector);

function basicBuySellSetup( env e, address receiver) {
    require receiver != currentContract;
    require receiver != _ghoReserve;
    require e.msg.sender != currentContract;
    require UNDERLYING_ASSET(e) != _ghoToken;
    require UNDERLYING_ASSET(e) != _ghoReserve;
}


//*********************************************************************************************
// The following invariant is to avoid overflow in the balanceOf of GHO
//*********************************************************************************************
invariant inv_sumAllBalance_eq_totalSupply()
  sumAllBalance() == to_mathint(_ghoToken.totalSupply());

ghost sumAllBalance() returns mathint {
    init_state axiom sumAllBalance() == 0;
}

hook Sstore _ghoToken.balanceOf[KEY address a] uint256 balance (uint256 old_balance) {
  havoc sumAllBalance assuming sumAllBalance@new() == sumAllBalance@old() + balance - old_balance;
}

hook Sload uint256 balance _ghoToken.balanceOf[KEY address a] {
  require balance <= sumAllBalance();
}


function priceLimits(env e) {
  uint8 exp;
  require 5 <= exp;
  require exp <= 27;
  require getUnderlyingAssetUnits() == require_uint256((10^exp)) && getPriceRatio() >= 10^16 && getPriceRatio() <= 10^20;
}

function feeLimits(env e) {
  require
    currentContract.getSellFeeBP(e) <= 5000 &&
    currentContract.getBuyFeeBP(e) < 5000 &&
    (currentContract.getSellFeeBP(e) > 0 || currentContract.getBuyFeeBP(e) > 0);
}
