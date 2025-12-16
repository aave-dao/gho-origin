// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IGhoDirectFacilitator
 * @author Aave/TokenLogic
 * @notice Defines the behaviour of an GhoDirectFacilitator
 */
interface IGhoDirectFacilitator {
  /**
   * @notice Mint an amount of GHO to an address
   * @dev Only callable by address with MINTER_ROLE.
   * @param account The address receiving GHO
   * @param amount The amount of GHO to be minted
   */
  function mint(address account, uint256 amount) external;

  /**
   * @notice Burns an amount of GHO
   * @dev Only callable by address with BURNER_ROLE.
   * @param amount The amount of GHO to be burned
   */
  function burn(uint256 amount) external;

  /**
   * @notice Returns the identifier of the Minter Role
   * @return The bytes32 id hash of the Minter role
   */
  function MINTER_ROLE() external pure returns (bytes32);

  /**
   * @notice Returns the identifier of the Burner Role
   * @return The bytes32 id hash of the Burner role
   */
  function BURNER_ROLE() external pure returns (bytes32);

  /**
   * @notice Returns the address of the GHO token
   * @return The address of GHO token contract
   */
  function GHO_TOKEN() external view returns (address);
}
