
using FixedPriceStrategyHarness as _priceStrategy;
using FixedFeeStrategyHarness as _FixedFeeStrategy;
using GhoToken as _ghoToken;
using GhoReserve as _ghoReserve;
using DummyERC20A as the_underlyning;
using DummyERC20B as some_erc20;

/////////////////// Methods ////////////////////////

methods
{   
  function getAvailableLiquidity() external returns (uint256) envfree;

  // GSM.sol
  function getUsed() external returns (uint256) envfree;
  function getGhoTreasury() external returns (address) envfree;

  // priceStrategy
  function _priceStrategy.getAssetPriceInGho(uint256, bool roundUp) external returns(uint256) envfree;
  function _priceStrategy.getUnderlyingAssetUnits() external returns(uint256) envfree;
  function _priceStrategy.PRICE_RATIO() external returns(uint256) envfree;
  function _priceStrategy.getUnderlyingAssetDecimals() external returns(uint256) envfree;


  // feeStrategy
  function _FixedFeeStrategy.getBuyFeeBP() external returns(uint256) envfree;
  function _FixedFeeStrategy.getSellFeeBP() external returns(uint256) envfree;
  function _FixedFeeStrategy.getBuyFee(uint256) external returns(uint256) envfree;
  function _FixedFeeStrategy.getSellFee(uint256) external returns(uint256) envfree;
    
  // GhoToken
  //    function _ghoToken.getFacilitatorBucket(address) external returns (uint256, uint256) envfree;
  function _ghoToken.balanceOf(address) external returns (uint256) envfree;
  function _ghoToken.totalSupply() external returns(uint256) envfree;
  
  // GhoReserve
  function _ghoReserve.getUsage(address entity) external returns (uint256, uint256) envfree;


    
  // Harness
  function getPriceRatio() external returns (uint256) envfree;
  function getAccruedFees() external returns (uint256) envfree;
  function balanceOfUnderlying(address) external returns (uint256) envfree;
}

definition harnessOnlyMethods(method f) returns bool =
        (f.selector == sig:getAccruedFees().selector ||
        f.selector == sig:getPriceRatio().selector ||
        f.selector == sig:getExposureCap().selector ||
        f.selector == sig:getPriceRatio().selector ||
        f.selector == sig:getUnderlyingAssetUnits().selector ||
        f.selector == sig:getUnderlyingAssetDecimals().selector ||
        f.selector == sig:getAssetPriceInGho(uint256, bool).selector ||
        f.selector == sig:getAssetPriceInGho(uint256, bool).selector ||
        f.selector == sig:getSellFee(uint256).selector ||
        f.selector == sig:getBuyFee(uint256).selector ||
        f.selector == sig:getBuyFeeBP().selector ||
        f.selector == sig:getSellFeeBP().selector ||
        f.selector == sig:getPercMathPercentageFactor().selector ||
        f.selector == sig:balanceOfGho(address).selector ||
        f.selector == sig:getCurrentGhoBalance().selector ||
        f.selector == sig:getCurrentUnderlyingBalance().selector ||
        f.selector == sig:getGhoBalanceOfThis().selector ||
        f.selector == sig:giftGho(address, uint).selector ||
        f.selector == sig:giftUnderlyingAsset(address, uint).selector ||
        f.selector == sig:balanceOfUnderlying(address).selector ||
        f.selector == sig:getCurrentExposure().selector);

definition buySellAssetsFunctions(method f) returns bool =
        (f.selector == sig:buyAsset(uint256,address).selector ||
        f.selector == sig:buyAssetWithSig(address,uint256,address,uint256,bytes).selector ||
        f.selector == sig:sellAsset(uint256,address).selector ||
        f.selector == sig:sellAssetWithSig(address,uint256,address,uint256,bytes).selector);

function basicBuySellSetup( env e, address receiver){
  require receiver != currentContract;
  require receiver != _ghoReserve;
  require e.msg.sender != currentContract;
  require UNDERLYING_ASSET(e) != _ghoToken;
  require UNDERLYING_ASSET(e) != _ghoReserve;
}

//*********************************************************************************************
// The following ghosts and invariant are to avoid overflow in the balanceOf of GHO
//*********************************************************************************************
persistent ghost sumAllBalance() returns mathint {
    init_state axiom sumAllBalance() == 0;
}

hook Sstore _ghoToken.balanceOf[KEY address a] uint256 balance (uint256 old_balance) {
  havoc sumAllBalance assuming sumAllBalance@new() == sumAllBalance@old() + balance - old_balance;
}

hook Sload uint256 balance _ghoToken.balanceOf[KEY address a] {
  require balance <= sumAllBalance();
}

invariant inv_sumAllBalance_eq_totalSupply()
  sumAllBalance() == to_mathint(_ghoToken.totalSupply())
  filtered {f -> f.contract == _ghoToken}
/*  {
    preserved rescueTokens(address token, address to, uint256 amount) with (env e) {
      //      require token==GHO_TOKEN() || token==UNDERLYING_ASSET() || token==some_erc20;
      require token==_ghoToken || token==the_underlyning || token==some_erc20;
    }
    }*/


function priceLimits(env e) {
    uint8 exp;
    require 5 <= exp;
    require exp <= 27;
    require getUnderlyingAssetUnits(e) == require_uint256((10^exp)) && getPriceRatio(e) >= 10^16 && getPriceRatio(e) <= 10^20;
}

function feeLimits(env e) {
  require
    currentContract.getSellFeeBP(e) <= 5000 &&
    currentContract.getBuyFeeBP(e) < 5000 &&
    (currentContract.getSellFeeBP(e) > 0 || currentContract.getBuyFeeBP(e) > 0);
}
