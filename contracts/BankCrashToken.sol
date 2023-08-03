// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./Interest.sol";

/**
 * @title BankCrashTokenV1
 * @dev This is an ERC20 token contract with staking and reward features. It implements an upgradeable pattern via OpenZeppelin SDK.
 * It also contains methods to track bank crashes and calculate APY based on the crash events.
 */
import "hardhat/console.sol";

contract BankCrashToken is Initializable, ERC20Upgradeable, OwnableUpgradeable, Interest {
    using SafeMath for uint256;
    
    /**
    * @dev Prevent calling initialization method more than once.
    */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
    * @dev Initializes the contract, sets the name, symbol of token and mints initial supply to the deployer of contract.
    */
    function initialize() initializer public {
        __ERC20_init("BankCrashToken", "BASH");
        __Ownable_init();
        _mint(msg.sender, INITIAL_SUPPLY);
        totalStakes = 0;
        totalStakers = 0;
    }

    uint256 public constant INITIAL_SUPPLY = 420690000000 * (10 ** 18);

    /**
    * @dev Struct to hold data related to bank crash events
    */
    struct BankCrashEvents{
        uint256 bigCrash;
        uint256 mediumCrash;
        uint256 smallCrash;
    }

    /**
    * @dev Struct to hold data related to bank crash events
    */
    struct Stake {
        uint256 amount;
        uint256 createdAt;
        uint256 endAt;
        uint256 baseAPY;
        uint256 maximumAPY;
        uint256 closedAt;
        BankCrashEvents memento;
    }

    BankCrashEvents public bankCrashEvents;

    mapping(address => mapping(uint256 => Stake)) public stakes;

    mapping(address => uint256) public nextStakeId;

    /**
    * @dev Emitted when a new stake is created
    */
    event StakeCreated(address indexed user, uint256 stakeId, uint256 amount, uint256 endAt, uint256 baseAPY, uint256 maximumAPY);
    
    /**
    * @dev Emitted when a stake is removed
    */
    event StakeRemoved(address indexed user, uint256 stakeId, uint256 amount, uint256 reward);

    /**
    * @dev Emitted when new bank crash events are added
    */
    event BankCrashEventAdded(address indexed user, bool, bool, bool);

    // Total locked amount of stakes
    uint256 public totalStakes;

    // Total number of current stakers
    uint256 public totalStakers;

    // Mapping from user to number of active stakes.
    mapping(address => uint) public activeStakes;

    // 17 August 2023 0:00:00 GMT
    uint256 public constant stakingRewardHalveningStart = 1692230400;

    /**
    * @notice Enables users to stake tokens
    * @param _amount The amount of tokens to stake
    * @param _months The length of the stake in months
    * @dev Transfers tokens from the user to the contract and creates a new Stake
    */
    function stake(uint256 _amount, uint256 _months) external {
        require(_months > 2, "Staking period must be at least 3 months");
        require(_months <= 120, "Staking period can only be maximum 120 months (10 years)");
        require(_amount > 0, "Staking amount must be greater than zero");

        // Transfer the tokens to this contract
        this.transferFrom(msg.sender, address(this), _amount);

        uint256 baseAPY = 10;

        // Maximum_apy = 69 + month * 3
        uint256 maxAPY = 69 + _months * 3 / 2;

        uint256 start = block.timestamp;
        uint256 end = block.timestamp.add(_months.mul(30 days));

        // Create a new stake
        stakes[msg.sender][nextStakeId[msg.sender]] = Stake(_amount, start, end, baseAPY, maxAPY, 0, BankCrashEvents(bankCrashEvents.bigCrash, bankCrashEvents.mediumCrash, bankCrashEvents.smallCrash));

        if (activeStakes[msg.sender] == 0) {
            totalStakers++;
        }

        activeStakes[msg.sender]++;

        totalStakes += _amount;

        emit StakeCreated(msg.sender, nextStakeId[msg.sender], _amount, end, baseAPY, maxAPY);
        
        // Increment the next stake ID for this user
        nextStakeId[msg.sender] = nextStakeId[msg.sender].add(1);
    }

    /**
    * @notice Allows users to remove a stake
    * @param _stakeId The ID of the stake to remove
    * @dev Checks that the stake exists, calculates the reward, applies a penalty for early unstaking, mints and transfers reward
    */
    function unstake(uint256 _stakeId) external {
        require(stakes[msg.sender][_stakeId].createdAt > 0, "This stake does not exist");
        require(stakes[msg.sender][_stakeId].closedAt == 0, "This stake has already been unstaked");
        Stake storage userStake = stakes[msg.sender][_stakeId];
        uint256 bonusApy = getBonusAPY(userStake);
        uint256 finalApy = userStake.baseAPY.add(bonusApy);

        uint256 reward = calculateReward(finalApy, userStake);
        uint256 rewardWithPenalty = userStake.amount.add(reward).mul(getStakePenalty(_stakeId)).div(100);

        _mint(
            address(this),
            rewardWithPenalty
        );

        this.transfer(msg.sender, rewardWithPenalty);

        stakes[msg.sender][_stakeId].closedAt = block.timestamp;

        activeStakes[msg.sender]--;

        totalStakes -= userStake.amount;

        // If this was the user's last stake, decrement totalStakers.
        if (activeStakes[msg.sender] == 0) {
            totalStakers--;
        }

        emit StakeRemoved(msg.sender, _stakeId, userStake.amount, rewardWithPenalty);
    }

    /**
    * @notice Calculates the penalty for early unstaking
    * @param _stakeId The ID of the stake to get penalty
    * @return The penalty as a percentage of the reward
    * @dev Penalizes early unstaking. No penalty if stake is completed. 67% penalty if unstaked within first 60 days. Linear penalty based on completed stake afterwards.
    */
    function getStakePenalty(uint256 _stakeId) public view returns (uint256) {
        require(stakes[msg.sender][_stakeId].createdAt > 0, "This stake does not exist");
        Stake storage userStake = stakes[msg.sender][_stakeId];

        uint256 totalStakingDuration = userStake.endAt.sub(userStake.createdAt);
        uint256 completedStake = block.timestamp.sub(userStake.createdAt);
        
        if(block.timestamp > userStake.endAt) {
            return 100;
        }
        if(block.timestamp < userStake.createdAt + 60 days) {
            return 10;
        } else {
            return 10 + 90 * completedStake / totalStakingDuration;
        }
    }

    /**
    * @notice Updates the number of 'Bank Crash' events
    * @param bigBankCrashEvent Indicates a 'Big Bank Crash' event
    * @param mediumBankCrashEvent Indicates a 'Medium Bank Crash' event
    * @param smallBankCrashEvent Indicates a 'Small Bank Crash' event
    * @dev Only callable by the owner. Increments the crash counters. At least one of the parameters must be true.
    */
    function updateBankCrashEvents(bool bigBankCrashEvent, bool mediumBankCrashEvent, bool smallBankCrashEvent) public onlyOwner {
        require(bigBankCrashEvent || mediumBankCrashEvent || smallBankCrashEvent, "At least one bank crash event should be true");

        if(bigBankCrashEvent) {
            bankCrashEvents.bigCrash++;
        }
        if(mediumBankCrashEvent) {
            bankCrashEvents.mediumCrash++;
        }
        if(smallBankCrashEvent) {
            bankCrashEvents.smallCrash++;
        }

        emit BankCrashEventAdded(msg.sender, bigBankCrashEvent, mediumBankCrashEvent, smallBankCrashEvent);
    }

    /**
    * @notice Calculates the bonus APY based on 'Bank Crash' events
    * @param userStake The stake for which the bonus APY is calculated
    * @return The bonus APY amount
    * @dev Checks the number of each type of 'Bank Crash' events that have occurred since the user's stake was created, and calculates the bonus APY
    */
    function getBonusAPY(Stake memory userStake) public view returns (uint256) {
        uint256 bigBankCollapses = bankCrashEvents.bigCrash - userStake.memento.bigCrash;
        uint256 mediumBankCollapses = bankCrashEvents.mediumCrash - userStake.memento.mediumCrash;
        uint256 smallBankCollapses = bankCrashEvents.smallCrash - userStake.memento.smallCrash;

        return bigBankCollapses * 42 + mediumBankCollapses * 14 + smallBankCollapses * 2;
    }

    /**
    * @notice Calculates the reward for a stake
    * @param finalApy The APY for the stake (baseAPY + bonusAPY)
    * @param userStake The stake for which the reward is calculated
    * @return The reward amount in wei
    * @dev Calculates the completed duration of the stake, calculates the final amount using the accrueInterest function, and calculates the reward
    */
    function calculateReward(uint256 finalApy, Stake memory userStake) internal view returns (uint256) {
        uint256 periodStart = userStake.createdAt;
        uint256 halvingPeriod = 2 * 365 days;
        uint256 totalReward = 0;

        // Calculate the number of periods that have passed since stakingRewardHalveningStart
        uint256 periods = (periodStart.sub(stakingRewardHalveningStart)).div(halvingPeriod);

        // Calculate the current period amount to calculate reward
        uint256 periodAmount = userStake.amount;

        while (periodStart < userStake.endAt) {
            
            uint256 periodEnd = periodStart + halvingPeriod;

            // Calculate the end of this period
            if(block.timestamp < periodEnd) {
                if (block.timestamp > userStake.endAt) {
                    periodEnd = userStake.endAt;
                } else {
                    periodEnd = block.timestamp;
                }
            }

            uint256 periodDuration = periodEnd.sub(periodStart);   

            if (periodDuration == 0) break;

            uint256 finalApyInWad = finalApy.mul(1 ether).div(100);

            uint256 reward = calculatePeriodicReward(periodAmount, periodDuration, periods, finalApyInWad);

            periodAmount = periodAmount.add(reward);
            
            // Add the reward for this period to the total reward
            totalReward = totalReward.add(reward);

            // Update the staking start for the next period
            periodStart = periodStart + periodDuration;
            periods = periods.add(1);
        }
        
        return totalReward;
    }

    /**
    * @dev Calculates the reward for a single period
    * @param periodAmount The principal amount for the period
    * @param periodDuration The duration of the period in seconds
    * @param periods The number of periods that have passed since stakingRewardHalveningStart
    * @param finalApyInWad The APY for the stake, in Wad format (baseAPY + bonusAPY)
    * @return The reward amount in wei for the given period
    */
    function calculatePeriodicReward(uint256 periodAmount, uint256 periodDuration, uint256 periods, uint256 finalApyInWad) internal pure returns (uint256) {
        uint256 periodApyInWad = finalApyInWad.div(2 ** periods);
        uint256 interestRate = yearlyRateToRay(periodApyInWad);
        uint256 principalInRay = periodAmount.mul(10 ** 27);
        uint256 finalAmount = accrueInterest(principalInRay, interestRate, periodDuration);
        uint256 reward = finalAmount.sub(principalInRay).div(10 ** 27);
        return reward;
    }

    function getStakes() external view returns (Stake[] memory) {
        Stake[] memory stakesArray = new Stake[](nextStakeId[msg.sender]);
        for (uint256 i = 0; i < nextStakeId[msg.sender]; i++) {
            stakesArray[i] = stakes[msg.sender][i];
        }
        return stakesArray;
    }
}
