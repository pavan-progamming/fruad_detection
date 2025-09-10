// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title FraudDetection
 * @dev A decentralized fraud detection and reporting system
 * @author Your Name
 */
contract FraudDetection {
    
    // Struct to represent a fraud report
    struct FraudReport {
        uint256 id;
        address reporter;
        address suspectedFraudster;
        string description;
        string evidenceHash; // IPFS hash of evidence
        uint256 timestamp;
        uint256 stake;
        ReportStatus status;
        uint256 confirmations;
        uint256 rejections;
        bool resolved;
    }
    
    // Enum for report status
    enum ReportStatus {
        Pending,
        UnderReview,
        Confirmed,
        Rejected
    }
    
    // State variables
    mapping(uint256 => FraudReport) public fraudReports;
    mapping(address => uint256[]) public userReports;
    mapping(address => uint256) public fraudScore; // Higher score = more fraudulent
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    
    uint256 public reportCounter;
    uint256 public constant MIN_STAKE = 0.01 ether;
    uint256 public constant VOTING_THRESHOLD = 3;
    uint256 public constant FRAUD_SCORE_THRESHOLD = 100;
    
    address public owner;
    
    // Events
    event FraudReported(
        uint256 indexed reportId,
        address indexed reporter,
        address indexed suspectedFraudster,
        uint256 stake
    );
    
    event ReportVoted(
        uint256 indexed reportId,
        address indexed voter,
        bool support
    );
    
    event ReportResolved(
        uint256 indexed reportId,
        ReportStatus finalStatus,
        address suspectedFraudster,
        uint256 newFraudScore
    );
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier validReport(uint256 _reportId) {
        require(_reportId < reportCounter, "Invalid report ID");
        require(!fraudReports[_reportId].resolved, "Report already resolved");
        _;
    }
    
    modifier hasNotVoted(uint256 _reportId) {
        require(!hasVoted[_reportId][msg.sender], "Already voted on this report");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        reportCounter = 0;
    }
    
    /**
     * @dev Submit a fraud report with evidence
     * @param _suspectedFraudster Address of the suspected fraudster
     * @param _description Description of the fraudulent activity
     * @param _evidenceHash IPFS hash of supporting evidence
     */
    function reportFraud(
        address _suspectedFraudster,
        string memory _description,
        string memory _evidenceHash
    ) external payable {
        require(msg.value >= MIN_STAKE, "Insufficient stake amount");
        require(_suspectedFraudster != address(0), "Invalid address");
        require(_suspectedFraudster != msg.sender, "Cannot report yourself");
        require(bytes(_description).length > 0, "Description required");
        
        uint256 reportId = reportCounter;
        
        fraudReports[reportId] = FraudReport({
            id: reportId,
            reporter: msg.sender,
            suspectedFraudster: _suspectedFraudster,
            description: _description,
            evidenceHash: _evidenceHash,
            timestamp: block.timestamp,
            stake: msg.value,
            status: ReportStatus.Pending,
            confirmations: 0,
            rejections: 0,
            resolved: false
        });
        
        userReports[msg.sender].push(reportId);
        reportCounter++;
        
        emit FraudReported(reportId, msg.sender, _suspectedFraudster, msg.value);
    }
    
    /**
     * @dev Vote on a fraud report (community verification)
     * @param _reportId ID of the report to vote on
     * @param _support True to confirm fraud, false to reject
     */
    function voteOnReport(uint256 _reportId, bool _support) 
        external 
        validReport(_reportId) 
        hasNotVoted(_reportId) 
    {
        require(msg.sender != fraudReports[_reportId].reporter, "Reporter cannot vote");
        require(msg.sender != fraudReports[_reportId].suspectedFraudster, "Accused cannot vote");
        
        hasVoted[_reportId][msg.sender] = true;
        
        if (_support) {
            fraudReports[_reportId].confirmations++;
        } else {
            fraudReports[_reportId].rejections++;
        }
        
        fraudReports[_reportId].status = ReportStatus.UnderReview;
        
        emit ReportVoted(_reportId, msg.sender, _support);
        
        // Check if voting threshold is met
        if (fraudReports[_reportId].confirmations + fraudReports[_reportId].rejections >= VOTING_THRESHOLD) {
            _resolveReport(_reportId);
        }
    }
    
    /**
     * @dev Resolve a fraud report based on community votes
     * @param _reportId ID of the report to resolve
     */
    function _resolveReport(uint256 _reportId) internal {
        FraudReport storage report = fraudReports[_reportId];
        
        if (report.confirmations > report.rejections) {
            // Fraud confirmed
            report.status = ReportStatus.Confirmed;
            fraudScore[report.suspectedFraudster] += 50;
            
            // Reward reporter (keep their stake + small bonus from contract)
            payable(report.reporter).transfer(report.stake);
            
        } else {
            // Fraud rejected
            report.status = ReportStatus.Rejected;
            
            // Penalize false reporter (lose stake)
            // Stake remains in contract as penalty
        }
        
        report.resolved = true;
        
        emit ReportResolved(
            _reportId, 
            report.status, 
            report.suspectedFraudster, 
            fraudScore[report.suspectedFraudster]
        );
    }
    
    /**
     * @dev Get fraud score of an address
     * @param _address Address to check
     * @return Current fraud score
     */
    function getFraudScore(address _address) external view returns (uint256) {
        return fraudScore[_address];
    }
    
    /**
     * @dev Check if an address is flagged as high-risk
     * @param _address Address to check
     * @return True if address has high fraud score
     */
    function isHighRisk(address _address) external view returns (bool) {
        return fraudScore[_address] >= FRAUD_SCORE_THRESHOLD;
    }
    
    /**
     * @dev Get report details
     * @param _reportId ID of the report
     * @return Complete report information
     */
    function getReport(uint256 _reportId) external view returns (FraudReport memory) {
        require(_reportId < reportCounter, "Invalid report ID");
        return fraudReports[_reportId];
    }
    
    /**
     * @dev Get all reports made by a user
     * @param _user Address of the user
     * @return Array of report IDs
     */
    function getUserReports(address _user) external view returns (uint256[] memory) {
        return userReports[_user];
    }
    
    /**
     * @dev Emergency function to resolve stuck reports (owner only)
     * @param _reportId ID of the report to force resolve
     * @param _confirm True to confirm fraud, false to reject
     */
    function forceResolveReport(uint256 _reportId, bool _confirm) 
        external 
        onlyOwner 
        validReport(_reportId) 
    {
        FraudReport storage report = fraudReports[_reportId];
        
        if (_confirm) {
            report.status = ReportStatus.Confirmed;
            fraudScore[report.suspectedFraudster] += 25; // Lower penalty for manual resolution
            payable(report.reporter).transfer(report.stake);
        } else {
            report.status = ReportStatus.Rejected;
        }
        
        report.resolved = true;
        
        emit ReportResolved(
            _reportId, 
            report.status, 
            report.suspectedFraudster, 
            fraudScore[report.suspectedFraudster]
        );
    }
    
    /**
     * @dev Withdraw contract balance (owner only)
     */
    function withdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
    
    /**
     * @dev Get contract balance
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
