// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/handle/HandleOwned.sol";

import {OzContext, OzContextBind} from "../../src/dependency/OzContext.sol";

import {ERC721Mock} from "../mocks/ERC721Mock.sol";

contract ValidSigner {
    bool private isSigner;
    address private acc;

    constructor(bool _isSigner, address acc_) {
        isSigner = _isSigner;
        acc = acc_;
    }

    function isValidSigner(address _acc, bytes calldata) external view returns (bytes4 magicValue) {
        if (_acc == acc && isSigner) {
            return 0x523e3260;
        }
        return 0x0;
    }
}

contract TestDummy {}

contract TestHandleOwned is OzContextBind, HandleOwned {
    constructor(address handleContract) HandleOwned(handleContract) {}

    function checkOwner() public view {
        super._checkOwner();
    }

    function isValidSigner(address acc) public view returns (bool) {
        return _isValidSigner(acc);
    }

    function protected() public view onlyOwner {}
}

contract HandleOwnedTest is Test, HandleOwnedErrors {
    TestHandleOwned private ho;

    ERC721Mock private token;

    function setUp() public {
        token = new ERC721Mock("test", "test");

        ho = new TestHandleOwned(address(token));
    }

    function testOwner(address owner) public {
        vm.assume(owner != address(0) && owner != address(this));
        TestHandleOwned o = new TestHandleOwned(address(token));

        token.mint(owner, uint256(uint160(address(o))));

        assertEq(o.owner(), owner, "token owner is contract owner");
    }

    function testOwner_nonExisting() public {
        TestHandleOwned o = new TestHandleOwned(address(token));

        vm.expectRevert();
        o.owner();
    }

    function testCheckOwner(address sender, address owner) public {
        vm.assume(sender != address(0) && sender != address(this));
        vm.assume(owner != address(0) && owner != address(this));
        vm.assume(owner != sender);

        TestHandleOwned o = new TestHandleOwned(address(token));

        token.mint(owner, uint256(uint160(address(o))));

        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedAccount.selector, sender));
        o.checkOwner();
    }

    function testCheckOwner_isOwner(address owner) public {
        vm.assume(owner != address(0) && owner != address(this));

        TestHandleOwned o = new TestHandleOwned(address(token));

        token.mint(owner, uint256(uint160(address(o))));

        vm.startPrank(owner);
        o.checkOwner();
    }

    function testCheckOwner_isValidSigner(address acc) public {
        ValidSigner signer = new ValidSigner(true, acc);
        TestHandleOwned o = new TestHandleOwned(address(token));

        token.mint(address(signer), uint256(uint160(address(o))));

        vm.startPrank(acc);
        o.checkOwner();
    }

    function testCheckOwner_isNotValidSigner(address acc) public {
        ValidSigner signer = new ValidSigner(false, acc);
        TestHandleOwned o = new TestHandleOwned(address(token));

        token.mint(address(signer), uint256(uint160(address(o))));

        vm.startPrank(acc);
        vm.expectRevert();
        o.checkOwner();
    }

    function testCheckOwner_testDummy(address acc) public {
        TestDummy signer = new TestDummy();
        TestHandleOwned o = new TestHandleOwned(address(token));

        token.mint(address(signer), uint256(uint160(address(o))));

        vm.startPrank(acc);
        vm.expectRevert();
        o.checkOwner();
    }

    function testOnlyOwner(address sender, address owner) public {
        vm.assume(sender != address(0) && sender != address(this));
        vm.assume(owner != address(0) && owner != address(this));
        vm.assume(owner != sender);

        TestHandleOwned o = new TestHandleOwned(address(token));

        token.mint(owner, uint256(uint160(address(o))));

        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedAccount.selector, sender));
        o.protected();
    }

    function testOnlyOwner_isOwner(address owner) public {
        vm.assume(owner != address(0) && owner != address(this));

        TestHandleOwned o = new TestHandleOwned(address(token));

        token.mint(owner, uint256(uint160(address(o))));

        vm.startPrank(owner);
        o.protected();
    }

    function testIsValidSigner_eoa(address acc) public {
        assertFalse(ho.isValidSigner(acc), "random EOA is not a valid signer");
    }

    function testIsValidSigner_signerContract(address acc, bool result) public {
        ValidSigner signer = new ValidSigner(result, acc);

        vm.prank(acc);
        assertEq(ho.isValidSigner(address(signer)), result, "does not match signer result");
    }

    function testIsValidSigner_randomContract(address acc) public {
        TestDummy signer = new TestDummy();

        vm.prank(acc);
        assertFalse(ho.isValidSigner(address(signer)), "account contract does not implement valid signer func");
    }
}
