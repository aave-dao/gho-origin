import "methods4626_base.spec";

import "../shared/methods_divint_summary.spec";
import "../shared/shared.spec";
import "../shared/erc20.spec";
import "erc4626.spec";


using DummyERC20B as UNDERLYING_ASSET; // should have no effect

methods {
  // priceStrategy
  function _priceStrategy.getAssetPriceInGho(uint256, bool) external returns(uint256) envfree;
  function _priceStrategy.getUnderlyingAssetUnits() external returns(uint256) envfree;
  
  // feeStrategy
  function _FixedFeeStrategy.getBuyFeeBP() external returns(uint256) envfree;
  function _FixedFeeStrategy.getSellFeeBP() external returns(uint256) envfree;

  // GSM4626.sol
  //  function _.UNDERLYING_ASSET() external  => DISPATCHER(true);
}






// @title Rule checks that In the event the underlying asset increases in value relative
// to the amount of GHO minted, excess yield harvesting should never result
// in previously-minted GHO having less backing (i.e., as new GHO is minted backed
// by the excess, it should not result in the GSM becoming under-backed in the same block).
// STATUS: VIOLATED
// Run:
rule yieldNeverDecreasesBacking() {
  env e;
  require(getExceed(e) > 0);
  cumulateYieldInGho(e);
  assert getDearth(e) == 0;
}

// @title Rule checks that _accruedFees should be <= ghotoken.balanceof(this) with an exception of the function distributeFeesToTreasury().
// STATUS: PASS
// Run: 
rule accruedFeesLEGhoBalanceOfThis(method f) {
  env e;
  calldataarg args;

  require(getAccruedFee(e) <= getGhoBalanceOfThis(e));
  require(e.msg.sender != currentContract);
  requireInvariant inv_sumAllBalance_eq_totalSupply();

  if (f.selector == sig:buyAssetWithSig(address,uint256,address,uint256,bytes).selector) {
    address originator;
    uint256 amount;
    address receiver;
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
// Run:

rule accruedFeesNeverDecrease(method f) filtered {f -> f.selector != sig:distributeFeesToTreasury().selector} {
    env e;
    calldataarg args;
    uint256 feesBefore = getAccruedFee(e);

    f(e,args);

    assert feesBefore <= getAccruedFee(e);
}


// @title For price ratio == 1, the total assets of a user should not increase.
// STATUS: VIOLATED
// https://prover.certora.com/output/11775/8448c89e18e94cb9a9ba21eb95b2efb0?anonymousKey=6f9f80c71040f75b35dece32a73442f84140e6ce
//  https://prover.certora.com/output/31688/4f70640081d6419fa999271d91a4ba89?anonymousKey=877a8c262875da9a8c04bda11d0c36facf5aa390
// Passing with Antti's model of 4626 (with some timeouts) https://prover.certora.com/output/31688/7c83d14232934b349d17569688a741fe?anonymousKey=0b7f3177ea39762c6d9fa1be1f7b969bda29f233
//
// For price ratio == 1, the total assets of a user should not increase
rule totalAssetsNotIncrease(method f) filtered {f -> f.selector != sig:seize().selector
    && f.selector != sig:rescueTokens(address, address, uint256).selector &&
	f.selector != sig:distributeFeesToTreasury().selector &&
	f.selector != sig:giftGho(address, uint256).selector &&
	f.selector != sig:giftUnderlyingAsset(address, uint256).selector &&
	f.selector != sig:buyAssetWithSig(address, uint256, address, uint256, bytes).selector &&
	f.selector != sig:sellAssetWithSig(address, uint256, address, uint256, bytes).selector} {
	env e;

	// we focus on a user so remove address of contracts
	require e.msg.sender != currentContract;

	require(getPriceRatio() == 10^18);
	// uint8 underlyingAssetDecimals;
	// require underlyingAssetDecimals <= 36;
	// require to_mathint(_priceStrategy.getUnderlyingAssetUnits()) == 10^underlyingAssetDecimals;
	feeLimits(e);
	priceLimits(e);
	mathint underlyingAssetUnits = _priceStrategy.getUnderlyingAssetUnits();

	address other;
	address receiver;
	uint256 amount;
	address originator;

	// This is here due to FixedPriceStrategy4626 since we need
	// to say that previewRedeem respects price ratio == 1, i.e.,
	// you still buy same amount of shares for the given gho.
	require(getAssetPriceInGho(e, amount, false) * underlyingAssetUnits/getPriceRatio() == to_mathint(amount));

	require receiver != currentContract; // && receiver != originator &&  receiver != e.msg.sender;
	require originator != currentContract; // && originator != e.msg.sender;
	require other != e.msg.sender && other != receiver && other != originator && other != currentContract;
	mathint totalAssetOtherBefore = getTotalAsset(e, other, getPriceRatio(), underlyingAssetUnits);

	mathint totalAssetBefore = assetOfUsers(e, e.msg.sender, receiver, originator, getPriceRatio(), underlyingAssetUnits);

	functionDispatcher(f, e, receiver, originator, amount);

	mathint totalAssetAfter = assetOfUsers(e, e.msg.sender, receiver, originator, getPriceRatio(), underlyingAssetUnits);

	assert totalAssetBefore >= totalAssetAfter;
	assert totalAssetOtherBefore == getTotalAsset(e, other, getPriceRatio(), underlyingAssetUnits);
}


// @title Rule checks that an overall asset of the system (UA - minted gho) stays same.
// STATUS: PASS
 
rule systemBalanceStabilitySell() {
  uint256 amount;
  address receiver;
  env e;
  require currentContract != e.msg.sender;
  require currentContract != receiver;

  feeLimits(e);
  priceLimits(e);
  //  require(getAssetPriceInGho(e, amount, false) * _priceStrategy.getUnderlyingAssetUnits()/getPriceRatio() == to_mathint(amount));

  mathint ghoUsedBefore = getUsed();
  mathint balanceBefore = balanceOfUnderlyingDirect(e, currentContract);
  
  sellAsset(e, amount, receiver);
  
  mathint ghoUsedAfter = getUsed();
  mathint balanceAfter = balanceOfUnderlyingDirect(e, currentContract);

  mathint diff = getAssetPriceInGho(e, assert_uint256(balanceAfter - balanceBefore), false) - ghoUsedAfter + ghoUsedBefore;
  //assert diff >= 0; // no underbacking
  assert diff >= 0 && diff <= 1;
}


// @title Rule checks that an overall asset of the system (UA - minted gho) stays same.
// STATUS: 
// 
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
  //  require (getAssetPriceInGho(e, amount, false) * _priceStrategy.getUnderlyingAssetUnits()/getPriceRatio() == to_mathint(amount) );
  
  uint256 limit;
  uint256 ghoUsedBefore;
  limit, ghoUsedBefore = getUsage(e); //getFacilitatorBucket(e);
  mathint balanceBefore = balanceOfUnderlyingDirect(e, currentContract);
  mathint ghoExceedBefore = getExceed(e);
  require limit - ghoUsedBefore > ghoExceedBefore;
  
  buyAsset(e, amount, receiver);
  
  mathint ghoUsedAfter = getUsed();
  mathint balanceAfter = balanceOfUnderlyingDirect(e, currentContract);
  
  
  mathint diff =
    getAssetPriceInGho(e, assert_uint256(balanceBefore - balanceAfter), true) - ghoUsedBefore + ghoUsedAfter - ghoExceedBefore;
  // assert diff <= 1; // No underbacking happens.
  assert -1 <= diff && diff <= 1;
}

