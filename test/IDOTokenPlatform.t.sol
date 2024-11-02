// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/IDOTokenPlatform.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// test token
contract TestToken is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {
        _mint(msg.sender, 1_000_000 * 10 ** decimals());
    }
}

contract IDOTokenPlatformTest is Test {
    IDOTokenPlatform public idoPlatform;
    TestToken public testToken;

    address public owner;
    address public alice;
    address public bob;

    uint256 public constant TOKEN_PRICE = 0.1 ether; // 1 token = 0.1 ETH
    uint256 public constant MIN_GOAL = 10 ether; // min goal 10 ETH
    uint256 public constant MAX_CAP = 20 ether; // max cap 20 ETH
    uint256 public constant DURATION = 7 days; // duration 7 days

    function setUp() public {
        owner = makeAddr("owner");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        // deploy contracts
        vm.startPrank(owner);
        idoPlatform = new IDOTokenPlatform();
        testToken = new TestToken();

        vm.stopPrank();
    }

    function test_CreateIDO() public {
        vm.startPrank(owner);

        // calculate required tokens: MAX_CAP * 1e18 / TOKEN_PRICE
        uint256 requiredTokens = (MAX_CAP * 1e18) / TOKEN_PRICE;

        // transfer enough tokens to IDO platform
        testToken.transfer(address(idoPlatform), requiredTokens);

        // create IDO
        idoPlatform.createIDO(address(testToken), TOKEN_PRICE, 18, MIN_GOAL, MAX_CAP, DURATION);

        // verify IDO info
        (
            IERC20 token,
            uint256 tokenPrice,
            uint256 minGoal,
            uint256 maxCap,
            uint256 startTime,
            uint256 endTime,
            uint256 totalRaised,
            bool claimed,
            bool exists
        ) = idoPlatform.getIDOInfo(1);

        assertEq(address(token), address(testToken));
        assertEq(tokenPrice, TOKEN_PRICE);
        assertEq(minGoal, MIN_GOAL);
        assertEq(maxCap, MAX_CAP);
        assertEq(endTime - startTime, DURATION);
        assertEq(totalRaised, 0);
        assertEq(claimed, false);
        assertEq(exists, true);

        vm.stopPrank();
    }

    function test_Contribute() public {
        vm.startPrank(owner);
        // calculate required tokens: MAX_CAP * 1e18 / TOKEN_PRICE
        uint256 requiredTokens = (MAX_CAP * 1e18) / TOKEN_PRICE;

        // transfer enough tokens to IDO platform
        testToken.transfer(address(idoPlatform), requiredTokens);

        // create IDO
        idoPlatform.createIDO(address(testToken), TOKEN_PRICE, 18, MIN_GOAL, MAX_CAP, DURATION);
        vm.stopPrank();

        // Alice invests 1 ETH
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        idoPlatform.contribute{ value: 1 ether }(1);

        // verify Alice's investment info
        (uint256 contribution, bool claimed) = idoPlatform.getUserInfo(1, alice);
        assertEq(contribution, 1 ether);
        assertEq(claimed, false);
    }

    function test_ClaimTokensSuccessful() public {
        // create IDO
        vm.startPrank(owner);

        // calculate required tokens: MAX_CAP * 1e18 / TOKEN_PRICE
        uint256 requiredTokens = (MAX_CAP * 1e18) / TOKEN_PRICE;

        // transfer enough tokens to IDO platform
        testToken.transfer(address(idoPlatform), requiredTokens);

        idoPlatform.createIDO(address(testToken), TOKEN_PRICE, 18, MIN_GOAL, MAX_CAP, DURATION);
        vm.stopPrank();

        // Alice and Bob invest enough to reach MIN_GOAL
        vm.deal(alice, 6 ether);
        vm.deal(bob, 5 ether);

        vm.prank(alice);
        idoPlatform.contribute{ value: 6 ether }(1);

        vm.prank(bob);
        idoPlatform.contribute{ value: 5 ether }(1);

        // fast forward to IDO end
        vm.warp(block.timestamp + DURATION + 1);

        // Alice claims tokens
        vm.prank(alice);
        idoPlatform.claimTokens(1);

        // verify Alice's token balance
        uint256 expectedTokens = (6 ether * 1e18) / TOKEN_PRICE;
        assertEq(testToken.balanceOf(alice), expectedTokens);
    }

    function test_ClaimRefundFailed() public {
        // create IDO
        vm.startPrank(owner);

        // calculate required tokens: MAX_CAP * 1e18 / TOKEN_PRICE
        uint256 requiredTokens = (MAX_CAP * 1e18) / TOKEN_PRICE;

        // transfer enough tokens to IDO platform
        testToken.transfer(address(idoPlatform), requiredTokens);

        idoPlatform.createIDO(address(testToken), TOKEN_PRICE, 18, MIN_GOAL, MAX_CAP, DURATION);
        vm.stopPrank();

        // Alice invests 1 ETH
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        idoPlatform.contribute{ value: 1 ether }(1);

        // fast forward to IDO end
        vm.warp(block.timestamp + DURATION + 1);

        // Alice claims refund
        vm.prank(alice);
        idoPlatform.claimRefund(1);

        // verify Alice received refund
        assertEq(alice.balance, 1 ether);
    }

    function testFail_ContributeAfterEnd() public {
        // create IDO
        vm.startPrank(owner);

        // calculate required tokens: MAX_CAP * 1e18 / TOKEN_PRICE
        uint256 requiredTokens = (MAX_CAP * 1e18) / TOKEN_PRICE;

        // transfer enough tokens to IDO platform
        testToken.transfer(address(idoPlatform), requiredTokens);

        idoPlatform.createIDO(address(testToken), TOKEN_PRICE, 18, MIN_GOAL, MAX_CAP, DURATION);
        vm.stopPrank();

        // fast forward to IDO end
        vm.warp(block.timestamp + DURATION + 1);

        // Alice tries to invest (should fail)
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        idoPlatform.contribute{ value: 1 ether }(1);
    }

    function testFail_ExceedMaxCap() public {
        // create IDO
        vm.startPrank(owner);

        // calculate required tokens: MAX_CAP * 1e18 / TOKEN_PRICE
        uint256 requiredTokens = (MAX_CAP * 1e18) / TOKEN_PRICE;

        // transfer enough tokens to IDO platform
        testToken.transfer(address(idoPlatform), requiredTokens);

        idoPlatform.createIDO(address(testToken), TOKEN_PRICE, 18, MIN_GOAL, MAX_CAP, DURATION);
        vm.stopPrank();

        // Alice tries to invest more than max cap (should fail)
        vm.deal(alice, 21 ether);
        vm.prank(alice);
        idoPlatform.contribute{ value: 21 ether }(1);
    }
}
