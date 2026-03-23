// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ReputationEngine {
    address public owner;
    address public taskManager;

    struct Review {
        uint256 taskId;
        address reviewer;
        uint8 rating;
        string comment;
        uint256 timestamp;
    }

    struct Reputation {
        uint256 totalRatings;
        uint256 totalScore;
        uint256 totalTasks;
    }

    mapping(address => Reputation) private _reputations;
    mapping(address => Review[]) private _reviews;

    event AgentRated(
        address indexed agent,
        address indexed reviewer,
        uint256 taskId,
        uint8 rating
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "ReputationEngine: caller is not the owner");
        _;
    }

    modifier onlyTaskManager() {
        require(msg.sender == taskManager, "ReputationEngine: caller is not the TaskManager");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setTaskManager(address _taskManager) external onlyOwner {
        require(_taskManager != address(0), "ReputationEngine: zero address");
        taskManager = _taskManager;
    }

    function rateAgent(
        address agent,
        uint256 taskId,
        uint8 rating,
        string calldata comment
    ) external onlyTaskManager {
        require(agent != address(0), "ReputationEngine: zero address agent");
        require(rating >= 1 && rating <= 5, "ReputationEngine: rating must be 1-5");

        _reviews[agent].push(Review({
            taskId: taskId,
            reviewer: tx.origin,
            rating: rating,
            comment: comment,
            timestamp: block.timestamp
        }));

        Reputation storage rep = _reputations[agent];
        rep.totalRatings += 1;
        rep.totalScore += rating;
        rep.totalTasks += 1;

        emit AgentRated(agent, tx.origin, taskId, rating);
    }

    function getReputation(address agent)
        external
        view
        returns (uint256 totalTasks, uint256 avgRatingX100, uint256 totalRatings)
    {
        Reputation storage rep = _reputations[agent];
        totalTasks = rep.totalTasks;
        totalRatings = rep.totalRatings;
        if (rep.totalRatings > 0) {
            avgRatingX100 = (rep.totalScore * 100) / rep.totalRatings;
        } else {
            avgRatingX100 = 0;
        }
    }

    function getReviews(address agent, uint256 offset, uint256 limit)
        external
        view
        returns (Review[] memory)
    {
        Review[] storage allReviews = _reviews[agent];
        uint256 total = allReviews.length;

        if (offset >= total) {
            return new Review[](0);
        }

        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }
        uint256 count = end - offset;

        Review[] memory result = new Review[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = allReviews[offset + i];
        }
        return result;
    }

    function getReviewCount(address agent) external view returns (uint256) {
        return _reviews[agent].length;
    }
}
