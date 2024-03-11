// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RewardsReceiver {
    // indexed by loan address then reward token address
    mapping(address => mapping(address => uint256)) public totalRewardsPerLoan;
    mapping(address => mapping(address => uint256)) public lastRewardAmountPerLoan;
    mapping(address => mapping(address => uint256)) public lastRewardTimestampPerLoan;

    mapping(address => HistoricalPayment[]) public userPaymentHistory;

    mapping(address => bool) public Admins;
    modifier OnlyAdmin(){
        require(Admins[msg.sender], "Only Admin");
        _;
    }

    struct HistoricalPayment {
        address loan;
        address token;
        uint256 amount;
        uint256 timestamp;
    }

    struct RewardData {
        uint256 totalRewards;
        uint256 lastRewardAmount;
        uint256 lastRewardTimestamp;
    }

    constructor(address [] memory _admins) {
        for(uint256 i = 0; i < _admins.length; i++){
            Admins[_admins[i]] = true;
        }
        Admins[msg.sender] = true;
    }

    function SendRewards(address[] memory _loan, address[] memory _token, uint256[] memory _reward) public {
        require((_loan.length == _token.length) && (_loan.length == _reward.length), "Arrays not same length");
        for (uint256 i = 0; i < _loan.length; i++) {
            UpdateRewardData(_loan[i], _token[i], _reward[i], msg.sender);
            IERC20(_token[i]).transferFrom(msg.sender, address(this), _reward[i]);
        }
    }

    // Owner functions
    function WithdrawRewards(address _token, uint256 _amount) public OnlyAdmin {
        IERC20(_token).transfer(msg.sender, _amount);
    }

    function ResetTotalLoanRewards(address _loan, address _token) public OnlyAdmin {
        totalRewardsPerLoan[_loan][_token] = 0;
    }

    // View functions
    function GetLoanRewardData(address _loan, address _token) external view returns (RewardData memory) {
        return RewardData({
            totalRewards: totalRewardsPerLoan[_loan][_token],
            lastRewardAmount: lastRewardAmountPerLoan[_loan][_token],
            lastRewardTimestamp: lastRewardTimestampPerLoan[_loan][_token]
        });
    }

    function GetUserPaymentHistory() external view returns (HistoricalPayment[] memory) {
        return userPaymentHistory[msg.sender];
    }

    // Internal functions
    function UpdateRewardData(address _loan, address _token, uint256 _reward, address _user) internal {
        totalRewardsPerLoan[_loan][_token] += _reward;
        lastRewardAmountPerLoan[_loan][_token] = _reward;
        lastRewardTimestampPerLoan[_loan][_token] = block.timestamp;
        userPaymentHistory[_user].push(HistoricalPayment({
            loan: _loan,
            token: _token,
            amount: _reward,
            timestamp: block.timestamp
        }));
    }
}
