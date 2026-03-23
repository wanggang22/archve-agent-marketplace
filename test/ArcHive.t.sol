// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AgentRegistry.sol";
import "../src/TaskManager.sol";
import "../src/ReputationEngine.sol";
import "../src/NanopayDemo.sol";

// =============================================================================
// MockUSDC — minimal ERC-20 mock for testing
// =============================================================================
contract MockUSDC {
    string public name     = "USD Coin";
    string public symbol   = "USDC";
    uint8  public decimals = 6;

    mapping(address => uint256)                      public balanceOf;
    mapping(address => mapping(address => uint256))  public allowance;
    uint256 public totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply   += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "MockUSDC: insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to]         += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "MockUSDC: insufficient balance");
        require(allowance[from][msg.sender] >= amount, "MockUSDC: insufficient allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from]             -= amount;
        balanceOf[to]               += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

// =============================================================================
// ArcHiveTest — comprehensive test suite for all ArcHive contracts
// =============================================================================
contract ArcHiveTest is Test {

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    address constant USDC_ADDR = 0x3600000000000000000000000000000000000000;
    uint256 constant ONE_USDC  = 1_000_000; // 6 decimals

    // -------------------------------------------------------------------------
    // Contracts under test
    // -------------------------------------------------------------------------
    AgentRegistry    public registry;
    TaskManager      public taskMgr;
    ReputationEngine public repEngine;
    NanopayDemo      public nanopay;
    MockUSDC         public usdc;

    // -------------------------------------------------------------------------
    // Actors
    // -------------------------------------------------------------------------
    address owner   = address(this);
    address agent1  = makeAddr("agent1");
    address agent2  = makeAddr("agent2");
    address client1 = makeAddr("client1");
    address client2 = makeAddr("client2");
    address nobody  = makeAddr("nobody");

    // -------------------------------------------------------------------------
    // setUp — deploy everything, wire contracts together, fund actors
    // -------------------------------------------------------------------------
    function setUp() public {
        // Deploy MockUSDC and etch its code at the hardcoded USDC_TOKEN address
        usdc = new MockUSDC();
        vm.etch(USDC_ADDR, address(usdc).code);

        // Deploy core contracts (owner = address(this))
        registry  = new AgentRegistry();
        taskMgr   = new TaskManager(address(registry));
        repEngine = new ReputationEngine();
        nanopay   = new NanopayDemo();

        // Wire contracts together
        registry.setTaskManager(address(taskMgr));
        taskMgr.setReputationEngine(address(repEngine));
        repEngine.setTaskManager(address(taskMgr));

        // Mint USDC to clients via the etched mock
        MockUSDC usdcAtAddr = MockUSDC(USDC_ADDR);
        usdcAtAddr.mint(client1, 1_000 * ONE_USDC);
        usdcAtAddr.mint(client2, 1_000 * ONE_USDC);

        // Register agent1 by default for convenience
        _registerDefaultAgent(agent1, "Agent-1");
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    function _registerDefaultAgent(address agent, string memory agentName) internal {
        string[] memory tags = new string[](2);
        tags[0] = "coding";
        tags[1] = "audit";
        vm.prank(agent);
        registry.registerAgent(agentName, "A helpful agent", "https://agent.example.com", 10 * ONE_USDC, tags);
    }

    /// @dev Client creates a task assigned to agent, handling USDC approval + creation.
    function _createTask(address client, address agent, uint256 payment) internal returns (uint256 taskId) {
        vm.prank(client);
        MockUSDC(USDC_ADDR).approve(address(taskMgr), payment);
        vm.prank(client);
        taskId = taskMgr.createTask(agent, "Do something useful", payment);
    }

    /// @dev Drive a task through Created -> InProgress -> Completed -> Approved.
    function _fullyApproveTask(address client, address agent, uint256 payment) internal returns (uint256 taskId) {
        taskId = _createTask(client, agent, payment);
        vm.prank(agent);
        taskMgr.acceptTask(taskId);
        vm.prank(agent);
        taskMgr.completeTask(taskId, "ipfs://result");
        vm.prank(client);
        taskMgr.approveTask(taskId);
    }

    // =========================================================================
    //  AGENT REGISTRY TESTS
    // =========================================================================

    function testRegisterAgent() public {
        // agent1 already registered in setUp; verify fields
        AgentRegistry.Agent memory a = registry.getAgent(agent1);
        assertEq(a.name, "Agent-1");
        assertEq(a.description, "A helpful agent");
        assertEq(a.endpoint, "https://agent.example.com");
        assertEq(a.pricePerTask, 10 * ONE_USDC);
        assertEq(a.skillTags.length, 2);
        assertEq(a.skillTags[0], "coding");
        assertEq(a.skillTags[1], "audit");
        assertTrue(a.active);
        assertGt(a.registeredAt, 0);
        assertEq(a.totalTasks, 0);
        assertEq(a.totalEarned, 0);
        assertTrue(registry.isRegistered(agent1));
    }

    function testRegisterAgentTwiceFails() public {
        // agent1 is already registered
        string[] memory tags = new string[](0);
        vm.prank(agent1);
        vm.expectRevert("AgentRegistry: already registered");
        registry.registerAgent("Agent-1-dup", "dup", "https://dup.com", ONE_USDC, tags);
    }

    function testUpdateAgent() public {
        string[] memory newTags = new string[](1);
        newTags[0] = "research";
        vm.prank(agent1);
        registry.updateAgent("Agent-1-v2", "Updated desc", "https://v2.example.com", 20 * ONE_USDC, newTags);

        AgentRegistry.Agent memory a = registry.getAgent(agent1);
        assertEq(a.name, "Agent-1-v2");
        assertEq(a.description, "Updated desc");
        assertEq(a.endpoint, "https://v2.example.com");
        assertEq(a.pricePerTask, 20 * ONE_USDC);
        assertEq(a.skillTags.length, 1);
        assertEq(a.skillTags[0], "research");
    }

    function testDeactivateActivate() public {
        // Deactivate
        vm.prank(agent1);
        registry.deactivateAgent();
        assertFalse(registry.isAgentActive(agent1));

        // Can't deactivate again
        vm.prank(agent1);
        vm.expectRevert("AgentRegistry: already inactive");
        registry.deactivateAgent();

        // Re-activate
        vm.prank(agent1);
        registry.activateAgent();
        assertTrue(registry.isAgentActive(agent1));

        // Can't activate again
        vm.prank(agent1);
        vm.expectRevert("AgentRegistry: already active");
        registry.activateAgent();
    }

    function testUnregisterAgent() public {
        vm.prank(agent1);
        registry.unregisterAgent();

        AgentRegistry.Agent memory a = registry.getAgent(agent1);
        assertEq(bytes(a.name).length, 0);
        assertEq(a.pricePerTask, 0);
        assertFalse(a.active);
        assertEq(a.registeredAt, 0);
        assertFalse(registry.isRegistered(agent1));
        assertFalse(registry.isAgentActive(agent1));
    }

    function testSkillTagsLimit() public {
        // 21 tags should revert
        string[] memory tags = new string[](21);
        for (uint256 i = 0; i < 21; i++) {
            tags[i] = "tag";
        }
        vm.prank(agent2);
        vm.expectRevert("AgentRegistry: too many tags");
        registry.registerAgent("TooMany", "desc", "https://x.com", ONE_USDC, tags);
    }

    function testGetAgentsPaginated() public {
        // Register agent2 so we have 2 agents total
        _registerDefaultAgent(agent2, "Agent-2");

        // Full page
        (AgentRegistry.Agent[] memory agents, address[] memory addrs) = registry.getAgentsPaginated(0, 10);
        assertEq(agents.length, 2);
        assertEq(addrs[0], agent1);
        assertEq(addrs[1], agent2);

        // Offset past end returns empty
        (agents, addrs) = registry.getAgentsPaginated(5, 10);
        assertEq(agents.length, 0);

        // Limit clamping
        (agents, addrs) = registry.getAgentsPaginated(1, 10);
        assertEq(agents.length, 1);
        assertEq(addrs[0], agent2);
    }

    function testOnlyOwnerSetTaskManager() public {
        vm.prank(nobody);
        vm.expectRevert("AgentRegistry: caller is not the owner");
        registry.setTaskManager(address(0xBEEF));
    }

    function testTransferOwnership() public {
        address newOwner = makeAddr("newOwner");

        // Propose
        registry.transferOwnership(newOwner);
        assertEq(registry.pendingOwner(), newOwner);

        // Non-pending can't accept
        vm.prank(nobody);
        vm.expectRevert("AgentRegistry: caller is not the pending owner");
        registry.acceptOwnership();

        // Pending owner accepts
        vm.prank(newOwner);
        registry.acceptOwnership();
        assertEq(registry.owner(), newOwner);
        assertEq(registry.pendingOwner(), address(0));
    }

    function testIsAgentActive() public {
        assertTrue(registry.isAgentActive(agent1));
        assertFalse(registry.isAgentActive(nobody)); // not registered
    }

    // =========================================================================
    //  TASK MANAGER TESTS
    // =========================================================================

    function testCreateTask() public {
        uint256 payment = 10 * ONE_USDC;
        uint256 taskId = _createTask(client1, agent1, payment);

        TaskManager.Task memory t = taskMgr.getTask(taskId);
        assertEq(t.client, client1);
        assertEq(t.agent, agent1);
        assertEq(t.payment, payment);
        assertEq(uint256(t.state), uint256(TaskManager.TaskState.Created));
        assertGt(t.createdAt, 0);

        // USDC was escrowed
        assertEq(MockUSDC(USDC_ADDR).balanceOf(address(taskMgr)), payment);
    }

    function testCannotHireSelf() public {
        // agent1 tries to create a task for itself
        vm.prank(agent1);
        MockUSDC(USDC_ADDR).approve(address(taskMgr), 10 * ONE_USDC);

        vm.prank(agent1);
        vm.expectRevert("TaskManager: cannot hire yourself");
        taskMgr.createTask(agent1, "self task", 10 * ONE_USDC);
    }

    function testAcceptTask() public {
        uint256 taskId = _createTask(client1, agent1, 10 * ONE_USDC);

        vm.prank(agent1);
        taskMgr.acceptTask(taskId);

        TaskManager.Task memory t = taskMgr.getTask(taskId);
        assertEq(uint256(t.state), uint256(TaskManager.TaskState.InProgress));
        assertGt(t.acceptedAt, 0);
    }

    function testCompleteTask() public {
        uint256 taskId = _createTask(client1, agent1, 10 * ONE_USDC);
        vm.prank(agent1);
        taskMgr.acceptTask(taskId);

        vm.prank(agent1);
        taskMgr.completeTask(taskId, "ipfs://QmResult");

        TaskManager.Task memory t = taskMgr.getTask(taskId);
        assertEq(uint256(t.state), uint256(TaskManager.TaskState.Completed));
        assertEq(t.resultHash, "ipfs://QmResult");
        assertGt(t.completedAt, 0);
    }

    function testApproveTask() public {
        uint256 payment = 10 * ONE_USDC;
        uint256 agentBalBefore = MockUSDC(USDC_ADDR).balanceOf(agent1);

        uint256 taskId = _fullyApproveTask(client1, agent1, payment);

        TaskManager.Task memory t = taskMgr.getTask(taskId);
        assertEq(uint256(t.state), uint256(TaskManager.TaskState.Approved));

        // Agent received payment
        assertEq(MockUSDC(USDC_ADDR).balanceOf(agent1), agentBalBefore + payment);

        // Registry stats updated
        AgentRegistry.Agent memory a = registry.getAgent(agent1);
        assertEq(a.totalTasks, 1);
        assertEq(a.totalEarned, payment);
    }

    function testRateAgent() public {
        uint256 taskId = _fullyApproveTask(client1, agent1, 10 * ONE_USDC);

        vm.prank(client1);
        taskMgr.rateAgent(taskId, 5, "Excellent work!");

        // Verify reputation
        (uint256 totalTasks, uint256 avgRatingX100, uint256 totalRatings) = repEngine.getReputation(agent1);
        assertEq(totalTasks, 1);
        assertEq(totalRatings, 1);
        assertEq(avgRatingX100, 500); // 5.00 * 100
    }

    function testDuplicateRateFails() public {
        uint256 taskId = _fullyApproveTask(client1, agent1, 10 * ONE_USDC);

        vm.prank(client1);
        taskMgr.rateAgent(taskId, 4, "Good");

        vm.prank(client1);
        vm.expectRevert("TaskManager: task already rated");
        taskMgr.rateAgent(taskId, 5, "Trying again");
    }

    function testDisputeTask() public {
        uint256 taskId = _createTask(client1, agent1, 10 * ONE_USDC);
        vm.prank(agent1);
        taskMgr.acceptTask(taskId);
        vm.prank(agent1);
        taskMgr.completeTask(taskId, "ipfs://bad");

        vm.prank(client1);
        taskMgr.disputeTask(taskId);

        TaskManager.Task memory t = taskMgr.getTask(taskId);
        assertEq(uint256(t.state), uint256(TaskManager.TaskState.Disputed));
        assertGt(t.disputedAt, 0);
    }

    function testOwnerResolveDisputeFavorAgent() public {
        uint256 payment = 10 * ONE_USDC;
        uint256 taskId = _createTask(client1, agent1, payment);
        vm.prank(agent1);
        taskMgr.acceptTask(taskId);
        vm.prank(agent1);
        taskMgr.completeTask(taskId, "ipfs://result");
        vm.prank(client1);
        taskMgr.disputeTask(taskId);

        uint256 agentBalBefore = MockUSDC(USDC_ADDR).balanceOf(agent1);

        // Owner resolves in favor of agent
        taskMgr.ownerResolveDispute(taskId, true);

        TaskManager.Task memory t = taskMgr.getTask(taskId);
        assertEq(uint256(t.state), uint256(TaskManager.TaskState.Resolved));
        assertEq(MockUSDC(USDC_ADDR).balanceOf(agent1), agentBalBefore + payment);
    }

    function testOwnerResolveDisputeFavorClient() public {
        uint256 payment = 10 * ONE_USDC;
        uint256 taskId = _createTask(client1, agent1, payment);
        vm.prank(agent1);
        taskMgr.acceptTask(taskId);
        vm.prank(agent1);
        taskMgr.completeTask(taskId, "ipfs://result");
        vm.prank(client1);
        taskMgr.disputeTask(taskId);

        uint256 clientBalBefore = MockUSDC(USDC_ADDR).balanceOf(client1);

        // Owner resolves in favor of client (refund)
        taskMgr.ownerResolveDispute(taskId, false);

        TaskManager.Task memory t = taskMgr.getTask(taskId);
        assertEq(uint256(t.state), uint256(TaskManager.TaskState.Resolved));
        assertEq(MockUSDC(USDC_ADDR).balanceOf(client1), clientBalBefore + payment);
    }

    function testAutoApproveTask() public {
        uint256 payment = 10 * ONE_USDC;
        uint256 taskId = _createTask(client1, agent1, payment);
        vm.prank(agent1);
        taskMgr.acceptTask(taskId);
        vm.prank(agent1);
        taskMgr.completeTask(taskId, "ipfs://result");

        // Too early
        vm.expectRevert("TaskManager: auto-approve timeout not reached");
        taskMgr.autoApproveTask(taskId);

        // Warp past 72h
        vm.warp(block.timestamp + 72 hours + 1);

        uint256 agentBalBefore = MockUSDC(USDC_ADDR).balanceOf(agent1);
        taskMgr.autoApproveTask(taskId);

        TaskManager.Task memory t = taskMgr.getTask(taskId);
        assertEq(uint256(t.state), uint256(TaskManager.TaskState.Approved));
        assertEq(MockUSDC(USDC_ADDR).balanceOf(agent1), agentBalBefore + payment);
    }

    function testCancelTask() public {
        uint256 payment = 10 * ONE_USDC;
        uint256 clientBalBefore = MockUSDC(USDC_ADDR).balanceOf(client1);
        uint256 taskId = _createTask(client1, agent1, payment);

        // Balance decreased after escrow
        assertEq(MockUSDC(USDC_ADDR).balanceOf(client1), clientBalBefore - payment);

        vm.prank(client1);
        taskMgr.cancelTask(taskId);

        TaskManager.Task memory t = taskMgr.getTask(taskId);
        assertEq(uint256(t.state), uint256(TaskManager.TaskState.Cancelled));

        // Full refund
        assertEq(MockUSDC(USDC_ADDR).balanceOf(client1), clientBalBefore);
    }

    function testReclaimTask() public {
        uint256 payment = 10 * ONE_USDC;
        uint256 clientBalBefore = MockUSDC(USDC_ADDR).balanceOf(client1);
        uint256 taskId = _createTask(client1, agent1, payment);

        // Too early to reclaim
        vm.prank(client1);
        vm.expectRevert("TaskManager: accept timeout not reached");
        taskMgr.reclaimTask(taskId);

        // Warp past 48h
        vm.warp(block.timestamp + 48 hours + 1);
        vm.prank(client1);
        taskMgr.reclaimTask(taskId);

        TaskManager.Task memory t = taskMgr.getTask(taskId);
        assertEq(uint256(t.state), uint256(TaskManager.TaskState.Cancelled));
        assertEq(MockUSDC(USDC_ADDR).balanceOf(client1), clientBalBefore);
    }

    function testEmergencyWithdraw() public {
        uint256 payment = 10 * ONE_USDC;
        uint256 taskId = _createTask(client1, agent1, payment);

        // Too early
        vm.expectRevert("TaskManager: task is not old enough");
        taskMgr.emergencyWithdraw(taskId);

        // Warp past 30 days
        vm.warp(block.timestamp + 30 days + 1);

        uint256 ownerBalBefore = MockUSDC(USDC_ADDR).balanceOf(owner);
        taskMgr.emergencyWithdraw(taskId);

        TaskManager.Task memory t = taskMgr.getTask(taskId);
        assertEq(uint256(t.state), uint256(TaskManager.TaskState.Cancelled));
        assertEq(MockUSDC(USDC_ADDR).balanceOf(owner), ownerBalBefore + payment);
    }

    function testOnlyAgentCanAccept() public {
        uint256 taskId = _createTask(client1, agent1, 10 * ONE_USDC);

        vm.prank(nobody);
        vm.expectRevert("TaskManager: caller is not the assigned agent");
        taskMgr.acceptTask(taskId);

        // Another agent also can't accept
        _registerDefaultAgent(agent2, "Agent-2");
        vm.prank(agent2);
        vm.expectRevert("TaskManager: caller is not the assigned agent");
        taskMgr.acceptTask(taskId);
    }

    function testOnlyClientCanApprove() public {
        uint256 taskId = _createTask(client1, agent1, 10 * ONE_USDC);
        vm.prank(agent1);
        taskMgr.acceptTask(taskId);
        vm.prank(agent1);
        taskMgr.completeTask(taskId, "ipfs://result");

        // Agent can't approve
        vm.prank(agent1);
        vm.expectRevert("TaskManager: caller is not the client");
        taskMgr.approveTask(taskId);

        // Random person can't approve
        vm.prank(nobody);
        vm.expectRevert("TaskManager: caller is not the client");
        taskMgr.approveTask(taskId);
    }

    // =========================================================================
    //  REPUTATION ENGINE TESTS
    // =========================================================================

    function testRateAgentViaTaskManager() public {
        // Direct call to repEngine should fail (only TaskManager can call)
        vm.prank(client1);
        vm.expectRevert("ReputationEngine: caller is not the TaskManager");
        repEngine.rateAgent(agent1, 0, 5, "Great", client1);

        // Via TaskManager flow works (tested through testRateAgent above, but
        // let's do a quick sanity check)
        uint256 taskId = _fullyApproveTask(client1, agent1, 10 * ONE_USDC);
        vm.prank(client1);
        taskMgr.rateAgent(taskId, 4, "Solid work");

        (uint256 totalTasks,, uint256 totalRatings) = repEngine.getReputation(agent1);
        assertEq(totalTasks, 1);
        assertEq(totalRatings, 1);
    }

    function testGetReputation() public {
        // Create and rate two tasks to test averages
        uint256 taskId1 = _fullyApproveTask(client1, agent1, 10 * ONE_USDC);
        vm.prank(client1);
        taskMgr.rateAgent(taskId1, 4, "Good");

        uint256 taskId2 = _fullyApproveTask(client1, agent1, 10 * ONE_USDC);
        vm.prank(client1);
        taskMgr.rateAgent(taskId2, 2, "Could be better");

        (uint256 totalTasks, uint256 avgRatingX100, uint256 totalRatings) = repEngine.getReputation(agent1);
        assertEq(totalTasks, 2);
        assertEq(totalRatings, 2);
        // Average of 4 and 2 = 3.00 => 300
        assertEq(avgRatingX100, 300);
    }

    function testGetReviewsPaginated() public {
        // Create 3 rated tasks
        for (uint256 i = 0; i < 3; i++) {
            uint256 taskId = _fullyApproveTask(client1, agent1, 10 * ONE_USDC);
            vm.prank(client1);
            taskMgr.rateAgent(taskId, uint8(3 + i), "Review");
        }

        // Total review count
        assertEq(repEngine.getReviewCount(agent1), 3);

        // First page (offset 0, limit 2)
        ReputationEngine.Review[] memory page1 = repEngine.getReviews(agent1, 0, 2);
        assertEq(page1.length, 2);
        assertEq(page1[0].rating, 3);
        assertEq(page1[1].rating, 4);

        // Second page
        ReputationEngine.Review[] memory page2 = repEngine.getReviews(agent1, 2, 2);
        assertEq(page2.length, 1);
        assertEq(page2[0].rating, 5);

        // Beyond range
        ReputationEngine.Review[] memory empty = repEngine.getReviews(agent1, 10, 5);
        assertEq(empty.length, 0);
    }

    // =========================================================================
    //  NANOPAY DEMO TESTS
    // =========================================================================

    function testRecordPayment() public {
        vm.prank(client1);
        nanopay.recordPayment(agent1, 500, "translation");

        assertEq(nanopay.getPaymentCount(), 1);

        NanopayDemo.NanopayRecord[] memory recs = nanopay.getPayments(0, 10);
        assertEq(recs.length, 1);
        assertEq(recs[0].payer, client1);
        assertEq(recs[0].agent, agent1);
        assertEq(recs[0].amount, 500);
        assertEq(recs[0].taskType, "translation");

        uint256[] memory agentIndices = nanopay.getPaymentsByAgent(agent1);
        assertEq(agentIndices.length, 1);
        assertEq(agentIndices[0], 0);
    }

    function testMaxRecords() public {
        // Fill up to MAX_RECORDS (1000)
        for (uint256 i = 0; i < 1000; i++) {
            nanopay.recordPayment(agent1, 1, "x");
        }
        assertEq(nanopay.getPaymentCount(), 1000);

        // The 1001st should revert
        vm.expectRevert("NanopayDemo: max records reached");
        nanopay.recordPayment(agent1, 1, "x");
    }

    function testTaskTypeTooLong() public {
        // Build a 101-character string
        bytes memory longBytes = new bytes(101);
        for (uint256 i = 0; i < 101; i++) {
            longBytes[i] = "A";
        }
        string memory longStr = string(longBytes);

        vm.expectRevert("NanopayDemo: taskType too long");
        nanopay.recordPayment(agent1, 1, longStr);
    }
}
