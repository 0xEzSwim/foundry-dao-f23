// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {Box} from "../src/Box.sol";
import {GovToken} from "../src/GovToken.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {Timelock} from "../src/Timelock.sol";

contract MyGovernortest is Test {
    MyGovernor private governor;
    Box private box;
    GovToken private govToken;
    Timelock private timelock;

    uint256 private constant INITIAL_SUPPLY = 100 ether;
    uint256 private constant MIN_DELAY = 1 hours;
    uint256 private constant VOTING_DELAY = 1;
    uint256 private constant VOTING_PERIOD = 50400;
    address private immutable i_user = makeAddr("user");

    address[] private proposers;
    address[] private executors;
    uint256[] private values;
    bytes[] private calldatas;
    address[] private targets;

    function setUp() external {
        govToken = new GovToken();
        govToken.mintGtk(i_user, INITIAL_SUPPLY);

        vm.startPrank(i_user);
        govToken.delegate(i_user);
        timelock = new Timelock(MIN_DELAY, proposers, executors, address(i_user));
        governor = new MyGovernor(govToken, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();
        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, address(i_user));
        vm.stopPrank();

        box = new Box(address(timelock));
    }

    function testCantUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(1);
    }

    function testGovernanceUpdatesBox() public {
        // Proposal:
        uint256 valueToStore = 888;
        string memory description = "store 888 in box";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", valueToStore);
        values.push(0);
        calldatas.push(encodedFunctionCall);
        targets.push(address(box));

        // 1. Propose to the DAO:
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        console.log("Proposal state: ", uint256(governor.state(proposalId)));
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);
        console.log("Proposal state: ", uint256(governor.state(proposalId)));

        // 2. Vote:
        string memory reason = "because bla bla bla";
        // 0 = Against, 1 = For, 2 = Abstain for this example
        uint8 voteWay = 1;
        vm.prank(i_user);
        governor.castVoteWithReason(proposalId, voteWay, reason);
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);
        console.log("Proposal State:", uint256(governor.state(proposalId)));

        //3. Queue the Transaction
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);
        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);
        console.log("Proposal State:", uint256(governor.state(proposalId)));

        // 4. Execute
        governor.execute(targets, values, calldatas, descriptionHash);
        console.log("Box number: ", box.getNumber());

        assert(box.getNumber() == valueToStore);
    }
}
