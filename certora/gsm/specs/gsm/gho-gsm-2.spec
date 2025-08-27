
import "methods_base.spec";
import "../shared/methods_divint_summary.spec";
import "../shared/shared.spec";
import "../shared/erc20.spec"; 

/*
methods {
  // priceStrategy
  function _priceStrategy.getAssetPriceInGho(uint256, bool) external returns(uint256) envfree;
  function _priceStrategy.getUnderlyingAssetUnits() external returns(uint256) envfree;
  function _priceStrategy.getUnderlyingAssetDecimals() external returns(uint256) envfree;
  
  // feeStrategy

  function _FixedFeeStrategy.getBuyFeeBP() external returns(uint256) envfree;
  function _FixedFeeStrategy.getSellFeeBP() external returns(uint256) envfree;

  //  function _ghoToken.totalSupply() external returns(uint256) envfree;
}
*/

//*********************************************************************************************
// The following invariant is to avoid overflow in the balanceOf of GHO
//*********************************************************************************************
/*
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
*/



// @title Rule checks that _accruedFees should be <= ghotoken.balanceof(this) with an exception of the function distributeFeesToTreasury().
// STATUS: PASS
rule accruedFeesLEGhoBalanceOfThis(method f) filtered {
  f -> !f.isView && !harnessOnlyMethods(f)}
{
  env e;
  calldataarg args;

  require(getAccruedFee(e) <= getGhoBalanceOfThis(e));
  require(e.msg.sender != currentContract);
  requireInvariant inv_sumAllBalance_eq_totalSupply();

  if (f.selector == sig:buyAssetWithSig(address,uint256,address,uint256,bytes).selector) {
    address receiver;
    uint256 amount;
    address originator;
    uint256 deadline;
    bytes signature;
    require(originator != currentContract);
    buyAssetWithSig(e, originator, amount, receiver, deadline, signature);
  } else {
    f(e,args);
  }

  assert getAccruedFee(e) <= getGhoBalanceOfThis(e);
}


// @title _accruedFees should never decrease, unless fees are being harvested by Treasury
// STATUS: PASS
// 
rule accruedFeesNeverDecrease(method f)
  filtered {f -> f.selector != sig:distributeFeesToTreasury().selector && !harnessOnlyMethods(f)}
{
  env e;
  calldataarg args;
  uint256 feesBefore = getAccruedFee(e);

  f(e,args);
  
  assert feesBefore <= getAccruedFee(e);
}


// @title For price ratio == 1, the total assets of a user should not increase
// STATUS: PASS
// 
rule totalAssetsNotIncrease(method f) filtered {f ->
    f.selector != sig:rescueTokens(address, address, uint256).selector &&
    f.selector != sig:buyAssetWithSig(address, uint256, address, uint256, bytes).selector &&
    f.selector != sig:sellAssetWithSig(address, uint256, address, uint256, bytes).selector &&
    !harnessOnlyMethods(f)
    } {
  env e;

  // we focus on a user so remove address of contracts
  require e.msg.sender != currentContract;
  require e.msg.sender != _ghoReserve;
  require e.msg.sender != getGhoTreasury();
  require e.msg.sender != 0;

  feeLimits(e);
  priceLimits(e);
  require(getPriceRatio() == 10^18);
  mathint underlyingAssetUnits = _priceStrategy.getUnderlyingAssetUnits();

  address other; address receiver; uint256 amount; address originator;

  require receiver != currentContract;   require receiver != _ghoReserve;   require receiver!=getGhoTreasury();
  require originator != currentContract; require originator != _ghoReserve; require originator!=getGhoTreasury();
  require other != currentContract;      require other != _ghoReserve;      require other!=getGhoTreasury();

  require other != e.msg.sender && other != receiver && other != originator;

  mathint totalAssetOtherBefore = getTotalAsset(e, other, getPriceRatio(), underlyingAssetUnits);
  mathint totalAssetBefore = assetOfUsers(e, e.msg.sender, receiver, originator, getPriceRatio(), underlyingAssetUnits);

  functionDispatcher(f, e, receiver, originator, amount);

  mathint totalAssetAfter = assetOfUsers(e, e.msg.sender, receiver, originator, getPriceRatio(), underlyingAssetUnits);

  assert totalAssetBefore >= totalAssetAfter;
  assert totalAssetOtherBefore == getTotalAsset(e, other, getPriceRatio(), underlyingAssetUnits);
}

// @title Rule checks that an overall asset of the system (UA - minted gho) stays same.
// STATUS: PASS
// https://prover.certora.com/output/31688/92138d4951324b81893fdfb04177dd6a/?anonymousKey=8fadc4e00f7004dfe3525dba321d29a8a9c31424
rule systemBalanceStabilityBuy() {
  uint256 amount;
  address receiver;
  env e;
  require e.msg.sender != currentContract;
  require e.msg.sender != _ghoToken;
  require e.msg.sender != _ghoReserve;
  require receiver != currentContract;

  feeLimits(e);
  priceLimits(e);

  mathint ghoUsedBefore = getUsed();
  mathint balanceBefore = getAssetPriceInGho(e, balanceOfUnderlying(e, currentContract), false) - ghoUsedBefore;

  buyAsset(e, amount, receiver);

  mathint ghoUsedAfter = getUsed();
  mathint balanceAfter = getAssetPriceInGho(e, balanceOfUnderlying(e, currentContract), false) - ghoUsedAfter;
  
  assert(balanceAfter + 1 >= balanceBefore && balanceAfter <= balanceBefore + 1);
}

// @title Rule checks that an overall asset of the system (UA - minted gho) stays same.
// STATUS: PASS
// 
rule systemBalanceStabilitySell() {
  uint256 amount;
  address receiver;
  env e;
  require currentContract != e.msg.sender;
  require currentContract != receiver;

  feeLimits(e);
  priceLimits(e);

  mathint ghoUsedBefore = getUsed();
  mathint balanceBefore = getPriceRatio()*balanceOfUnderlying(e, currentContract)/_priceStrategy.getUnderlyingAssetUnits() - ghoUsedBefore;

  sellAsset(e, amount, receiver);

  mathint ghoUsedAfter = getUsed();
  mathint balanceAfter = getPriceRatio()*balanceOfUnderlying(e, currentContract)/_priceStrategy.getUnderlyingAssetUnits() - ghoUsedAfter;

  assert balanceAfter + 1 >= balanceBefore;
}

