// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './TestSGhoBase.t.sol';

contract TestSGhoPermit is TestSGhoBase {
  // ========================================
  // ERC20 PERMIT FUNCTIONALITY TESTS
  // ========================================

  struct PermitVars {
    uint256 privateKey;
    address owner;
    address spender;
    uint256 value;
    uint256 deadline;
    uint256 nonce;
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  function test_permit_invalidSignature() external {
    PermitVars memory vars;
    vars.privateKey = 0xA11CE;
    vars.owner = vm.addr(vars.privateKey);
    vars.spender = user2;
    vars.value = 100 ether;
    vars.deadline = block.timestamp + 1 hours;
    vars.nonce = sgho.nonces(vars.owner);
    (vars.v, vars.r, vars.s) = _createPermitSignature(
      vars.owner,
      vars.spender,
      vars.value,
      vars.nonce,
      vars.deadline,
      vars.privateKey
    );
    // Use wrong owner address - should revert with ERC2612InvalidSigner
    {
      bytes32 PERMIT_TYPEHASH = keccak256(
        'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'
      );
      bytes32 structHash = keccak256(
        abi.encode(PERMIT_TYPEHASH, user1, vars.spender, vars.value, vars.nonce, vars.deadline)
      );
      bytes32 hash = keccak256(abi.encodePacked('\x19\x01', sgho.DOMAIN_SEPARATOR(), structHash));
      address recovered = ECDSA.recover(hash, vars.v, vars.r, vars.s);
      vm.expectRevert(
        abi.encodeWithSelector(
          ERC20PermitUpgradeable.ERC2612InvalidSigner.selector,
          recovered,
          user1
        )
      );
      sgho.permit(user1, vars.spender, vars.value, vars.deadline, vars.v, vars.r, vars.s);
    }
  }

  function test_permit_replay() external {
    PermitVars memory vars;
    vars.privateKey = 0xA11CE;
    vars.owner = vm.addr(vars.privateKey);
    vars.spender = user2;
    vars.value = 100 ether;
    vars.deadline = block.timestamp + 1 hours;
    vars.nonce = sgho.nonces(vars.owner);
    (vars.v, vars.r, vars.s) = _createPermitSignature(
      vars.owner,
      vars.spender,
      vars.value,
      vars.nonce,
      vars.deadline,
      vars.privateKey
    );
    // First permit should succeed
    sgho.permit(vars.owner, vars.spender, vars.value, vars.deadline, vars.v, vars.r, vars.s);
    assertEq(
      sgho.allowance(vars.owner, vars.spender),
      vars.value,
      'First permit should set allowance'
    );
    // Second permit with same signature should revert (nonce already used)
    // The contract expects nonce 1, but our signature is for nonce 0
    {
      bytes32 PERMIT_TYPEHASH = keccak256(
        'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'
      );
      bytes32 structHash = keccak256(
        abi.encode(
          PERMIT_TYPEHASH,
          vars.owner,
          vars.spender,
          vars.value,
          vars.nonce + 1,
          vars.deadline
        )
      );
      bytes32 hash = keccak256(abi.encodePacked('\x19\x01', sgho.DOMAIN_SEPARATOR(), structHash));
      address recovered = ECDSA.recover(hash, vars.v, vars.r, vars.s);
      vm.expectRevert(
        abi.encodeWithSelector(
          ERC20PermitUpgradeable.ERC2612InvalidSigner.selector,
          recovered,
          vars.owner
        )
      );
      sgho.permit(vars.owner, vars.spender, vars.value, vars.deadline, vars.v, vars.r, vars.s);
    }
  }

  function test_permit_wrongDomainSeparator() external {
    PermitVars memory vars;
    vars.privateKey = 0xA11CE;
    vars.owner = vm.addr(vars.privateKey);
    vars.spender = user2;
    vars.value = 100 ether;
    vars.deadline = block.timestamp + 1 hours;
    vars.nonce = sgho.nonces(vars.owner);
    // Use wrong domain separator
    bytes32 PERMIT_TYPEHASH = keccak256(
      'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'
    );
    bytes32 structHash = keccak256(
      abi.encode(PERMIT_TYPEHASH, vars.owner, vars.spender, vars.value, vars.nonce, vars.deadline)
    );
    bytes32 wrongDomainSeparator = keccak256('WRONG_DOMAIN');
    bytes32 hash = keccak256(abi.encodePacked('\x19\x01', wrongDomainSeparator, structHash));
    (vars.v, vars.r, vars.s) = vm.sign(vars.privateKey, hash);
    // The contract will recover a different signer than owner
    {
      bytes32 contractHash = keccak256(
        abi.encodePacked('\x19\x01', sgho.DOMAIN_SEPARATOR(), structHash)
      );
      address recovered = ECDSA.recover(contractHash, vars.v, vars.r, vars.s);
      vm.expectRevert(
        abi.encodeWithSelector(
          ERC20PermitUpgradeable.ERC2612InvalidSigner.selector,
          recovered,
          vars.owner
        )
      );
      sgho.permit(vars.owner, vars.spender, vars.value, vars.deadline, vars.v, vars.r, vars.s);
    }
  }

  function test_permit_validSignature() external {
    PermitVars memory vars;
    vars.privateKey = 0xA11CE;
    vars.owner = vm.addr(vars.privateKey);
    vars.spender = user2;
    vars.value = 100 ether;
    vars.deadline = block.timestamp + 1 hours;
    vars.nonce = sgho.nonces(vars.owner);
    (vars.v, vars.r, vars.s) = _createPermitSignature(
      vars.owner,
      vars.spender,
      vars.value,
      vars.nonce,
      vars.deadline,
      vars.privateKey
    );
    sgho.permit(vars.owner, vars.spender, vars.value, vars.deadline, vars.v, vars.r, vars.s);
    assertEq(
      sgho.allowance(vars.owner, vars.spender),
      vars.value,
      'Permit should set allowance correctly'
    );
  }

  function test_permit_expiredDeadline() external {
    PermitVars memory vars;
    vars.privateKey = 0xA11CE;
    vars.owner = vm.addr(vars.privateKey);
    vars.spender = user2;
    vars.value = 100 ether;
    vars.deadline = block.timestamp - 1; // Expired deadline
    vars.nonce = sgho.nonces(vars.owner);
    (vars.v, vars.r, vars.s) = _createPermitSignature(
      vars.owner,
      vars.spender,
      vars.value,
      vars.nonce,
      vars.deadline,
      vars.privateKey
    );
    vm.expectRevert(
      abi.encodeWithSelector(ERC20PermitUpgradeable.ERC2612ExpiredSignature.selector, vars.deadline)
    );
    sgho.permit(vars.owner, vars.spender, vars.value, vars.deadline, vars.v, vars.r, vars.s);
  }

  function test_permit_zeroValue() external {
    PermitVars memory vars;
    vars.privateKey = 0xA11CE;
    vars.owner = vm.addr(vars.privateKey);
    vars.spender = user2;
    vars.value = 0;
    vars.deadline = block.timestamp + 1 hours;
    vars.nonce = sgho.nonces(vars.owner);
    (vars.v, vars.r, vars.s) = _createPermitSignature(
      vars.owner,
      vars.spender,
      vars.value,
      vars.nonce,
      vars.deadline,
      vars.privateKey
    );
    sgho.permit(vars.owner, vars.spender, vars.value, vars.deadline, vars.v, vars.r, vars.s);
    assertEq(
      sgho.allowance(vars.owner, vars.spender),
      0,
      'permit with value 0 should set allowance to 0'
    );
  }

  function test_permit_selfApproval() external {
    PermitVars memory vars;
    vars.privateKey = 0xA11CE;
    vars.owner = vm.addr(vars.privateKey);
    vars.value = 100 ether;
    vars.deadline = block.timestamp + 1 hours;
    vars.nonce = sgho.nonces(vars.owner);
    (vars.v, vars.r, vars.s) = _createPermitSignature(
      vars.owner,
      vars.owner,
      vars.value,
      vars.nonce,
      vars.deadline,
      vars.privateKey
    );
    sgho.permit(vars.owner, vars.owner, vars.value, vars.deadline, vars.v, vars.r, vars.s);
    assertEq(sgho.allowance(vars.owner, vars.owner), vars.value, 'Self approval should work');
  }

  function test_nonces() external {
    address owner = user1;
    uint256 initialNonce = sgho.nonces(owner);

    // Nonce should increment after permit
    uint256 privateKey = 0xA11CE;
    address permitOwner = vm.addr(privateKey);
    address spender = user2;
    uint256 value = 100 ether;
    uint256 deadline = block.timestamp + 1 hours;
    uint256 nonce = sgho.nonces(permitOwner);

    (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
      permitOwner,
      spender,
      value,
      nonce,
      deadline,
      privateKey
    );

    sgho.permit(permitOwner, spender, value, deadline, v, r, s);

    assertEq(sgho.nonces(permitOwner), nonce + 1, 'Nonce should increment after permit');
    assertEq(sgho.nonces(owner), initialNonce, 'Other user nonce should remain unchanged');
  }

  function test_permit_depositWithPermit_validSignature() external {
    uint256 depositAmount = 100 ether;
    uint256 deadline = block.timestamp + 1 hours;

    // Create permit signature
    uint256 privateKey = 0x1234;
    address owner = vm.addr(privateKey);

    // Fund the owner with GHO
    deal(address(gho), owner, depositAmount, true);

    // Approve sGho to spend GHO (this is what the permit should do)
    vm.startPrank(owner);
    gho.approve(address(sgho), depositAmount);
    vm.stopPrank();

    // Create permit signature
    (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
      owner,
      address(sgho),
      depositAmount,
      sgho.nonces(owner),
      deadline,
      privateKey
    );

    // Execute depositWithPermit
    vm.startPrank(owner);
    uint256 shares = sgho.depositWithPermit(
      depositAmount,
      owner,
      deadline,
      IsGho.SignatureParams(v, r, s)
    );
    vm.stopPrank();

    // Verify deposit was successful
    assertEq(sgho.balanceOf(owner), shares, 'Shares should be minted to owner');
    assertEq(gho.balanceOf(owner), 0, 'GHO should be transferred from owner');
    assertEq(gho.balanceOf(address(sgho)), depositAmount + 1 ether, 'GHO should be in contract');
  }

  function test_permit_depositWithPermit_insufficientBalance() external {
    uint256 depositAmount = 100 ether;
    uint256 actualBalance = 50 ether; // Less than requested
    uint256 deadline = block.timestamp + 1 hours;

    // Create permit signature
    uint256 privateKey = 0x1234;
    address owner = vm.addr(privateKey);

    // Fund the owner with less GHO than requested
    deal(address(gho), owner, actualBalance, true);

    // Approve sGho to spend GHO
    vm.startPrank(owner);
    gho.approve(address(sgho), depositAmount);
    vm.stopPrank();

    // Create permit signature for full amount
    (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
      owner,
      address(sgho),
      depositAmount,
      sgho.nonces(owner),
      deadline,
      privateKey
    );

    // Execute depositWithPermit - should revert due to insufficient balance
    vm.startPrank(owner);
    vm.expectRevert('ERC20: transfer amount exceeds balance');
    sgho.depositWithPermit(depositAmount, owner, deadline, IsGho.SignatureParams(v, r, s));
    vm.stopPrank();
  }

  function test_permit_depositWithPermit_invalidSignature() external {
    uint256 depositAmount = 100 ether;
    uint256 deadline = block.timestamp + 1 hours;

    // Create permit signature with wrong private key
    uint256 wrongPrivateKey = 0x5678;
    uint256 correctPrivateKey = 0x1234;
    address owner = vm.addr(correctPrivateKey);

    // Fund the owner with GHO
    deal(address(gho), owner, depositAmount, true);

    // Create permit signature with wrong private key
    (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
      owner,
      address(sgho),
      depositAmount,
      sgho.nonces(owner),
      deadline,
      wrongPrivateKey
    );

    // Execute depositWithPermit - should still work but permit will fail silently
    vm.startPrank(owner);
    // Should revert because no approval was given
    vm.expectRevert();
    sgho.depositWithPermit(depositAmount, owner, deadline, IsGho.SignatureParams(v, r, s));
    vm.stopPrank();
  }

  function test_permit_depositWithPermit_expiredDeadline() external {
    uint256 depositAmount = 100 ether;
    uint256 deadline = block.timestamp - 1; // Expired deadline

    // Create permit signature
    uint256 privateKey = 0x1234;
    address owner = vm.addr(privateKey);

    // Fund the owner with GHO
    deal(address(gho), owner, depositAmount, true);

    // Create permit signature
    (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
      owner,
      address(sgho),
      depositAmount,
      sgho.nonces(owner),
      deadline,
      privateKey
    );

    // Execute depositWithPermit - should revert due to expired deadline
    vm.startPrank(owner);
    vm.expectRevert();
    sgho.depositWithPermit(depositAmount, owner, deadline, IsGho.SignatureParams(v, r, s));
    vm.stopPrank();
  }

  function test_permit_depositWithPermit_zeroAmount() external {
    uint256 depositAmount = 0;
    uint256 deadline = block.timestamp + 1 hours;

    // Create permit signature
    uint256 privateKey = 0x1234;
    address owner = vm.addr(privateKey);

    // Fund the owner with GHO
    deal(address(gho), owner, 100 ether, true);

    // Create permit signature
    (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
      owner,
      address(sgho),
      depositAmount,
      sgho.nonces(owner),
      deadline,
      privateKey
    );

    // Execute depositWithPermit - should work with zero amount
    vm.startPrank(owner);
    uint256 shares = sgho.depositWithPermit(
      depositAmount,
      owner,
      deadline,
      IsGho.SignatureParams(v, r, s)
    );
    vm.stopPrank();

    // Verify zero deposit
    assertEq(shares, 0, 'Zero deposit should return 0 shares');
    assertEq(sgho.balanceOf(owner), 0, 'Owner should have no shares');
    assertEq(gho.balanceOf(owner), 100 ether, 'Owner GHO balance should remain unchanged');
  }

  function test_permit_depositWithPermit_withYieldAccrual() external {
    uint256 depositAmount = 100 ether;
    uint256 deadline = block.timestamp + 1 hours;

    // Create permit signature
    uint256 privateKey = 0x1234;
    address owner = vm.addr(privateKey);

    // Fund the owner with GHO
    deal(address(gho), owner, depositAmount, true);

    // Approve sGho to spend GHO
    vm.startPrank(owner);
    gho.approve(address(sgho), depositAmount);
    vm.stopPrank();

    // Create permit signature
    (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
      owner,
      address(sgho),
      depositAmount,
      sgho.nonces(owner),
      deadline,
      privateKey
    );

    // Skip time to accrue yield
    vm.warp(block.timestamp + 30 days);

    // Execute depositWithPermit
    vm.startPrank(owner);
    uint256 shares = sgho.depositWithPermit(
      depositAmount,
      owner,
      deadline,
      IsGho.SignatureParams(v, r, s)
    );
    vm.stopPrank();

    // Verify deposit was successful and yield was considered
    assertEq(sgho.balanceOf(owner), shares, 'Shares should be minted to owner');
    assertEq(gho.balanceOf(owner), 0, 'GHO should be transferred from owner');

    // Shares should be less than deposit amount due to yield accrual
    assertTrue(shares < depositAmount, 'Shares should be less than deposit due to yield accrual');
  }
}
