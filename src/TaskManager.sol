// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// =============================================================================
// TaskManager.sol — Task creation, escrow, and lifecycle management
// Target: Arc Testnet (Chain ID 5042002)
// =============================================================================

// -----------------------------------------------------------------------------
// Minimal IERC20 interface (USDC on Arc Testnet, 6 decimals)
// -----------------------------------------------------------------------------
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

// -----------------------------------------------------------------------------
// AgentRegistry interface — the TaskManager relies on an external registry
// to validate agents and track completed-task counts.
// -----------------------------------------------------------------------------
interface IAgentRegistry {
    /// @notice Returns true when the agent address is registered AND active.
    function isAgentActive(address agent) external view returns (bool);

    /// @notice Increments the completed-task counter for the given agent.
    function incrementTasks(address agent, uint256 earned) external;
}

interface IReputationEngine {
    function rateAgent(address agent, uint256 taskId, uint8 rating, string calldata comment) external;
}

// =============================================================================
// TaskManager
// =============================================================================
contract TaskManager {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice USDC token on Arc Testnet (6 decimals).
    address public constant USDC_TOKEN = 0x3600000000000000000000000000000000000000;

    /// @notice Duration after which a dispute auto-resolves in favour of the agent.
    uint256 public constant DISPUTE_TIMEOUT = 24 hours;

    /// @notice Duration after which a client can reclaim a task the agent never accepted.
    uint256 public constant ACCEPT_TIMEOUT = 48 hours;

    // -------------------------------------------------------------------------
    // Enums & Structs
    // -------------------------------------------------------------------------

    enum TaskState {
        Created,
        InProgress,
        Completed,
        Approved,
        Disputed,
        Resolved,
        Cancelled
    }

    struct Task {
        address client;       // task creator / payer
        address agent;        // assigned agent
        string  description;  // human-readable task description
        uint256 payment;      // USDC amount (6 decimals)
        string  resultHash;   // deliverable hash submitted by agent
        TaskState state;      // current lifecycle state
        uint256 createdAt;    // block.timestamp when created
        uint256 acceptedAt;   // block.timestamp when agent accepted
        uint256 completedAt;  // block.timestamp when agent submitted result
    }

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /// @notice Contract owner (deployer).
    address public owner;

    /// @notice Reference to the AgentRegistry contract.
    IAgentRegistry public agentRegistry;

    /// @notice Reference to the ReputationEngine contract.
    IReputationEngine public reputationEngine;

    /// @notice All tasks, indexed by taskId (0-based).
    Task[] public tasks;

    /// @notice Mapping: client address => array of task IDs they created.
    mapping(address => uint256[]) private _clientTasks;

    /// @notice Mapping: agent address => array of task IDs assigned to them.
    mapping(address => uint256[]) private _agentTasks;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event TaskCreated(uint256 indexed taskId, address indexed client, address indexed agent, uint256 payment);
    event TaskAccepted(uint256 indexed taskId, address indexed agent);
    event TaskCompleted(uint256 indexed taskId, address indexed agent, string resultHash);
    event TaskApproved(uint256 indexed taskId, address indexed client, address indexed agent, uint256 payment);
    event TaskDisputed(uint256 indexed taskId, address indexed client);
    event TaskResolved(uint256 indexed taskId, address indexed agent, uint256 payment);
    event TaskCancelled(uint256 indexed taskId, address indexed client, uint256 refund);

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyOwner() {
        require(msg.sender == owner, "TaskManager: caller is not the owner");
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @param _agentRegistry Address of the deployed AgentRegistry contract.
    constructor(address _agentRegistry) {
        require(_agentRegistry != address(0), "TaskManager: zero address registry");
        owner = msg.sender;
        agentRegistry = IAgentRegistry(_agentRegistry);
    }

    // -------------------------------------------------------------------------
    // Core Functions
    // -------------------------------------------------------------------------

    /// @notice Create a new task and escrow USDC payment in this contract.
    /// @dev Caller must have approved this contract to spend `payment` USDC beforehand.
    /// @param agent   The agent assigned to the task (must be registered & active).
    /// @param description  Human-readable description of the work.
    /// @param payment USDC amount (6 decimals) to escrow.
    /// @return taskId The ID of the newly created task.
    function createTask(
        address agent,
        string calldata description,
        uint256 payment
    ) external returns (uint256 taskId) {
        require(agent != address(0), "TaskManager: zero address agent");
        require(payment > 0, "TaskManager: payment must be > 0");
        require(agentRegistry.isAgentActive(agent), "TaskManager: agent not registered or inactive");

        // Transfer USDC from client to this contract (escrow).
        IERC20 usdc = IERC20(USDC_TOKEN);
        require(
            usdc.transferFrom(msg.sender, address(this), payment),
            "TaskManager: USDC transfer failed"
        );

        // Create task.
        taskId = tasks.length;
        tasks.push(Task({
            client:      msg.sender,
            agent:       agent,
            description: description,
            payment:     payment,
            resultHash:  "",
            state:       TaskState.Created,
            createdAt:   block.timestamp,
            acceptedAt:  0,
            completedAt: 0
        }));

        // Track by client and agent.
        _clientTasks[msg.sender].push(taskId);
        _agentTasks[agent].push(taskId);

        emit TaskCreated(taskId, msg.sender, agent, payment);
    }

    /// @notice Agent accepts an assigned task. Transitions Created -> InProgress.
    /// @param taskId The task to accept.
    function acceptTask(uint256 taskId) external {
        Task storage t = _getTask(taskId);
        require(msg.sender == t.agent, "TaskManager: caller is not the assigned agent");
        require(t.state == TaskState.Created, "TaskManager: task is not in Created state");

        t.state = TaskState.InProgress;
        t.acceptedAt = block.timestamp;

        emit TaskAccepted(taskId, msg.sender);
    }

    /// @notice Agent submits a result for the task. Transitions InProgress -> Completed.
    /// @param taskId     The task to complete.
    /// @param resultHash Hash or reference to the deliverable.
    function completeTask(uint256 taskId, string calldata resultHash) external {
        Task storage t = _getTask(taskId);
        require(msg.sender == t.agent, "TaskManager: caller is not the assigned agent");
        require(t.state == TaskState.InProgress, "TaskManager: task is not InProgress");

        t.resultHash = resultHash;
        t.state = TaskState.Completed;
        t.completedAt = block.timestamp;

        emit TaskCompleted(taskId, msg.sender, resultHash);
    }

    /// @notice Client approves the completed work. Releases escrowed USDC to agent
    ///         and increments the agent's task count in the registry.
    ///         Transitions Completed -> Approved.
    /// @param taskId The task to approve.
    function approveTask(uint256 taskId) external {
        Task storage t = _getTask(taskId);
        require(msg.sender == t.client, "TaskManager: caller is not the client");
        require(t.state == TaskState.Completed, "TaskManager: task is not Completed");

        t.state = TaskState.Approved;

        // Release USDC to the agent.
        IERC20 usdc = IERC20(USDC_TOKEN);
        require(usdc.transfer(t.agent, t.payment), "TaskManager: USDC transfer to agent failed");

        // Update agent stats in registry.
        agentRegistry.incrementTasks(t.agent, t.payment);

        emit TaskApproved(taskId, msg.sender, t.agent, t.payment);
    }

    /// @notice Client rates the agent after task approval.
    function rateAgent(uint256 taskId, uint8 rating, string calldata comment) external {
        Task storage t = _getTask(taskId);
        require(msg.sender == t.client, "TaskManager: caller is not the client");
        require(t.state == TaskState.Approved || t.state == TaskState.Resolved, "TaskManager: task not approved/resolved");
        require(address(reputationEngine) != address(0), "TaskManager: reputation engine not set");
        reputationEngine.rateAgent(t.agent, taskId, rating, comment);
    }

    /// @notice Set the ReputationEngine contract address.
    function setReputationEngine(address _reputationEngine) external onlyOwner {
        require(_reputationEngine != address(0), "TaskManager: zero address");
        reputationEngine = IReputationEngine(_reputationEngine);
    }

    /// @notice Client disputes the completed work. Transitions Completed -> Disputed.
    /// @param taskId The task to dispute.
    function disputeTask(uint256 taskId) external {
        Task storage t = _getTask(taskId);
        require(msg.sender == t.client, "TaskManager: caller is not the client");
        require(t.state == TaskState.Completed, "TaskManager: task is not Completed");

        t.state = TaskState.Disputed;
        // Re-use completedAt as the dispute timestamp (the moment the state changes).
        // We store the dispute start time in completedAt since that field already holds
        // the completion timestamp and we need a reference point for the 24h timeout.
        // For clarity we overwrite completedAt with the dispute timestamp.
        t.completedAt = block.timestamp;

        emit TaskDisputed(taskId, msg.sender);
    }

    /// @notice Anyone can resolve a dispute after 24 hours. Auto-resolves in favour
    ///         of the agent (releases escrowed USDC). Transitions Disputed -> Resolved.
    /// @param taskId The disputed task.
    function resolveDispute(uint256 taskId) external {
        Task storage t = _getTask(taskId);
        require(t.state == TaskState.Disputed, "TaskManager: task is not Disputed");
        require(
            block.timestamp >= t.completedAt + DISPUTE_TIMEOUT,
            "TaskManager: dispute timeout not reached"
        );

        t.state = TaskState.Resolved;

        // Release USDC to the agent.
        IERC20 usdc = IERC20(USDC_TOKEN);
        require(usdc.transfer(t.agent, t.payment), "TaskManager: USDC transfer to agent failed");

        emit TaskResolved(taskId, t.agent, t.payment);
    }

    /// @notice Client cancels a task that has not been accepted yet.
    ///         Refunds escrowed USDC. Transitions Created -> Cancelled.
    /// @param taskId The task to cancel.
    function cancelTask(uint256 taskId) external {
        Task storage t = _getTask(taskId);
        require(msg.sender == t.client, "TaskManager: caller is not the client");
        require(t.state == TaskState.Created, "TaskManager: task is not in Created state");

        t.state = TaskState.Cancelled;

        // Refund USDC to client.
        IERC20 usdc = IERC20(USDC_TOKEN);
        require(usdc.transfer(t.client, t.payment), "TaskManager: USDC refund failed");

        emit TaskCancelled(taskId, msg.sender, t.payment);
    }

    /// @notice Client reclaims a task if the agent has not accepted within 48 hours.
    ///         Refunds escrowed USDC. Transitions Created -> Cancelled.
    /// @param taskId The task to reclaim.
    function reclaimTask(uint256 taskId) external {
        Task storage t = _getTask(taskId);
        require(msg.sender == t.client, "TaskManager: caller is not the client");
        require(t.state == TaskState.Created, "TaskManager: task is not in Created state");
        require(
            block.timestamp >= t.createdAt + ACCEPT_TIMEOUT,
            "TaskManager: accept timeout not reached"
        );

        t.state = TaskState.Cancelled;

        // Refund USDC to client.
        IERC20 usdc = IERC20(USDC_TOKEN);
        require(usdc.transfer(t.client, t.payment), "TaskManager: USDC refund failed");

        emit TaskCancelled(taskId, msg.sender, t.payment);
    }

    // -------------------------------------------------------------------------
    // View / Query Functions
    // -------------------------------------------------------------------------

    /// @notice Returns full Task struct for a given taskId.
    function getTask(uint256 taskId) external view returns (Task memory) {
        require(taskId < tasks.length, "TaskManager: task does not exist");
        return tasks[taskId];
    }

    /// @notice Returns the total number of tasks created.
    function getTaskCount() external view returns (uint256) {
        return tasks.length;
    }

    /// @notice Returns all task IDs created by a given client.
    function getTasksByClient(address client) external view returns (uint256[] memory) {
        return _clientTasks[client];
    }

    /// @notice Returns all task IDs assigned to a given agent.
    function getTasksByAgent(address agent) external view returns (uint256[] memory) {
        return _agentTasks[agent];
    }

    // -------------------------------------------------------------------------
    // Internal Helpers
    // -------------------------------------------------------------------------

    /// @dev Fetches a task by ID with bounds check, returning a storage pointer.
    function _getTask(uint256 taskId) internal view returns (Task storage) {
        require(taskId < tasks.length, "TaskManager: task does not exist");
        return tasks[taskId];
    }
}
