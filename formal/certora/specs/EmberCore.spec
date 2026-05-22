methods {
    function INITIAL_SUPPLY() external returns uint256 envfree;
    function totalBurned() external returns uint256 envfree;
    function totalRedeemed() external returns uint256 envfree;
    function totalSupply() external returns uint256 envfree;
    function released() external returns bool envfree;
    function slashed() external returns bool envfree;
    function abandonedRecovered() external returns bool envfree;
    function redemptionPoolTotal() external returns uint256 envfree;
    function redemptionSupplyTotal() external returns uint256 envfree;
    function redemptionPaid() external returns uint256 envfree;
    function redemptionReserveRemaining() external returns uint256 envfree;
    function feeBps() external returns uint256 envfree;
    function MAX_FEE_BPS() external returns uint256 envfree;
}

invariant burnedNeverExceedsInitial()
    totalBurned() <= INITIAL_SUPPLY();

invariant redeemedNeverExceedsRedemptionSupply()
    totalRedeemed() <= redemptionSupplyTotal();

invariant redemptionPaidNeverExceedsPool()
    redemptionPaid() <= redemptionPoolTotal();

invariant reserveRemainingNeverExceedsPool()
    redemptionReserveRemaining() <= redemptionPoolTotal();

invariant feeBpsWithinCap()
    feeBps() <= MAX_FEE_BPS();

rule terminalStatesAreMutuallyExclusive() {
    assert !(released() && slashed());
}

rule burnedPlusLiveSupplyBounded() {
    assert totalBurned() + totalSupply() <= INITIAL_SUPPLY();
}
