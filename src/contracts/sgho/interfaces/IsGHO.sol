// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.19;

/**
 * @title IsGHO Interface
 * @notice Interface for the sGHO contract, which is an ERC4626 vault for GHO tokens.
 */
interface IsGHO {
  // --- Custom Errors ---

  /**
   * @notice Thrown when a direct ETH transfer is attempted.
   */
  error NoEthAllowed();

  /**
   * @notice Thrown if the target rate is set to a value greater than the max rate.
   */
  error RateMustBeLessThanMaxRate();

  /**
   * @notice Thrown when a zero address is provided for a critical parameter during initialization.
   */
  error ZeroAddressNotAllowed();

  // --- Events ---

  /**
   * @notice Emitted when the target rate is updated.
   * @param newRate The new target rate.
   */
  event TargetRateUpdated(uint256 newRate);

  /**
   * @notice Emitted when the timestamp and yield index are updated.
   * @param timestamp The timestamp of the update.
   * @param currentRate The current yield index.
   */
  event ExchangeRateUpdate(uint256 timestamp, uint256 currentRate);

  /**
   * @notice Emitted when the supply cap is updated.
   * @param newSupplyCap The new supply cap.
   */
  event SupplyCapUpdated(uint256 newSupplyCap);

  /**
   * @notice Struct for signature parameters.
   * @param v The recovery ID of the signature.
   * @param r The R component of the signature.
   * @param s The S component of the signature.
   */
  struct SignatureParams {
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  // --- State Variables (as view functions) ---

  /**
   * @notice Returns the address of the GHO token used as the underlying asset in the vault.
   * @return The address of the GHO token.
   */
  function GHO() external view returns (address);

  /**
   * @notice Returns the total supply cap of the vault.
   * @return The total supply cap.
   */
  function supplyCap() external view returns (uint160);

  /**
   * @notice Returns the maximum safe rate for the vault.
   * @return The maximum safe rate.
   */
  function MAX_SAFE_RATE() external view returns (uint16);

  /**
   * @notice Returns the current yield index, representing the accumulated yield.
   * @dev This index is used to calculate the value of sGHO in terms of GHO.
   * @return The current yield index.
   */
  function yieldIndex() external view returns (uint176);

  /**
   * @notice Returns the current target annual percentage rate (APR) for yield generation.
   * @dev The rate is expressed in basis points (1% = 100).
   * @return The target rate in basis points.
   */
  function targetRate() external view returns (uint16);

  /**
   * @notice Returns the current rate per second for yield generation.
   * @dev The rate is expressed in basis points (1% = 100).
   * @return The rate per second multiplied by 10^27.
   */
  function ratePerSecond() external view returns (uint96);

  /**
   * @notice Returns the timestamp of the last time the yield index was updated.
   * @return The Unix timestamp of the last update.
   */
  function lastUpdate() external view returns (uint64);

  /**
   * @notice Returns the role identifier for the Funds Admin.
   * @dev This role has permissions to manage funds, such as rescuing tokens.
   * @return The keccak256 hash of "FUNDS_ADMIN_ROLE".
   */
  function FUNDS_ADMIN_ROLE() external view returns (bytes32);

  /**
   * @notice Returns the role identifier for the Yield Manager.
   * @dev This role has permissions to update the target rate.
   * @return The keccak256 hash of "YIELD_MANAGER_ROLE".
   */
  function YIELD_MANAGER_ROLE() external view returns (bytes32);

  // --- Functions ---

  /**
   * @notice Pauses the contract, can be called by `PAUSE_GUARDIAN_ROLE`.
   * Emits a {Paused} event.
   */
  function pause() external;

  /**
   * @notice Unpauses the contract, can be called by `PAUSE_GUARDIAN_ROLE`.
   * Emits a {Unpaused} event.
   */
  function unpause() external;

  /**
   * @notice Sets the target rate for yield generation.
   * @dev This function can only be called by an address with the YIELD_MANAGER role.
   * The new rate must be less than 50% (5000 basis points).
   * @param newRate The new target rate in basis points (e.g., 1000 for 10%).
   */
  function setTargetRate(uint16 newRate) external;

  /**
   * @notice Sets the supply cap for the vault.
   * @dev This function can only be called by an address with the YIELD_MANAGER role.
   * @param newSupplyCap The new supply cap.
   */
  function setSupplyCap(uint160 newSupplyCap) external;

  /**
   * @notice Deposits GHO into the vault using permit and mints sGHO shares to the receiver.
   * @dev This function allows users to deposit GHO without requiring a separate approve transaction.
   * The permit is used to approve the vault to spend the user's GHO tokens.
   * The yield index is updated before the deposit to ensure correct share calculation.
   * @param assets The amount of GHO to deposit.
   * @param receiver The address that will receive the sGHO shares.
   * @param deadline Must be a timestamp in the future.
   * @param sig A `secp256k1` signature params from `msgSender()`.
   * @return The amount of sGHO shares minted.
   */
  function depositWithPermit(
    uint256 assets,
    address receiver,
    uint256 deadline,
    SignatureParams memory sig
  ) external returns (uint256);
}
