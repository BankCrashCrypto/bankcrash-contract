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
 * Website is at: https://bankcrash.gg
 * White paper is at: https://docs.bankcrash.gg
 */
contract BankCrashTokenV1 is Initializable, ERC20Upgradeable, OwnableUpgradeable, Interest {
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
    }

    uint256 public constant INITIAL_SUPPLY = 42_000_000_000 * (10 ** 18);

    struct BankCrashEvents{
        uint256 bigCrash;
        uint256 mediumCrash;
        uint256 smallCrash;
    }

    struct Stake {
        uint256 amount;
        uint256 createdAt;
        uint256 endAt;
        uint256 closedAt;
        uint256 baseAPY;
        uint256 maximumAPY;
        BankCrashEvents memento;
    }

    BankCrashEvents public bankCrashEvents;

    mapping(address => mapping(uint256 => Stake)) public stakes;

    mapping(address => uint256) public nextStakeID;

    /**
    * @dev Emitted when a new stake is created
    */
    event StakeCreated(address indexed user, uint256 stakeID, uint256 amount, uint256 endAt, uint256 baseAPY, uint256 maximumAPY);
    
    /**
    * @dev Emitted when a stake is removed
    */
    event StakeRemoved(address indexed user, uint256 stakeID, uint256 amount, uint256 reward);

    /**
    * @dev Emitted when new bank crash events are added
    */
    event BankCrashEventAdded(address indexed user, bool, bool, bool);

    // Total locked amount of stakes
    uint256 public totalStakedAmount;

    // Total number of active stakers
    uint256 public activeStakers;

    // Mapping from user to number of active stakes.
    mapping(address => uint) public activeStakes;

    // 4 July 2023 0:00:00 GMT-4
    uint256 public constant stakingRewardHalveningStart = 1688443200;

    /**
    * @notice Allows users to lock in their tokens for staking.
    * @param _amount Amount of tokens the user wants to stake.
    * @param _months Duration for which the user wants to stake their tokens.
    * 
    * @dev 
    * - Validates the staking period and amount.
    * - Burns the staking amount from the user's balance, effectively locking it.
    * - Sets the base APY and calculates the max APY based on the staking duration.
    * - Records the staking details in the stakes mapping.
    * - Updates stakers count and total staked amount.
    * - Emits a `StakeCreated` event indicating the successful creation of the stake.
    * 
    * Requirements:
    * - Staking duration must be between 3 and 120 months.
    * - Staking amount must be greater than zero.
    */
    function stake(uint256 _amount, uint256 _months) external {
        require(_months >= 3, "Staking period must be at least 3 months");
        require(_months <= 120, "Staking period can only be maximum 120 months (10 years)");
        require(_amount > 0, "Staking amount must be greater than zero");

        _burn(msg.sender, _amount);

        uint256 baseAPY = 4;

        uint256 maxAPY = 42 + _months * 2;

        uint256 start = block.timestamp;
        uint256 end   = block.timestamp.add(_months.mul(30 days));

        uint256 stakeID = nextStakeID[msg.sender];
        nextStakeID[msg.sender]++;

        stakes[msg.sender][stakeID] = Stake(_amount, start, end, 0, baseAPY, maxAPY, BankCrashEvents(bankCrashEvents.bigCrash, bankCrashEvents.mediumCrash, bankCrashEvents.smallCrash));

        if (activeStakes[msg.sender] == 0) {
            activeStakers++;
        }        

        activeStakes[msg.sender]++;

        totalStakedAmount += _amount;

        emit StakeCreated(msg.sender, stakeID, _amount, end, baseAPY, maxAPY);
    }

    /**
    * @notice Allows users to remove a stake and claim rewards.
    * @param _stakeID The unique ID of the stake to be removed.
    * 
    * @dev 
    * - Validates that the stake exists and is active.
    * - Calculates the bonus and final APY.
    * - Computes the reward with consideration to any penalties for early unstaking.
    * - Mints the reward, updates the state, and transfers the amount to the user.
    * - Emits a `StakeRemoved` event.
    * 
    * Requirements:
    * - The stake with the given ID must exist.
    * - The stake must not have been previously unstaked.
    */
    function unstake(uint256 _stakeID) external {
        require(stakes[msg.sender][_stakeID].createdAt > 0, "This stake does not exist");
        require(stakes[msg.sender][_stakeID].closedAt == 0, "This stake has already been unstaked");
        Stake storage userStake = stakes[msg.sender][_stakeID];
        
        uint256 bonusApy = getBonusAPY(_stakeID);
        uint256 finalApy = userStake.baseAPY.add(bonusApy);

        uint256 reward = calculateReward(finalApy, userStake);
        uint256 userStakeWithReward = userStake.amount.add(reward);
        uint256 finalStakeReward = userStakeWithReward.mul(getStakePenalty(_stakeID)).div(100);

        _mint(
            address(this),
            finalStakeReward
        );
        this.transfer(msg.sender, finalStakeReward);

        stakes[msg.sender][_stakeID].closedAt = block.timestamp;
        totalStakedAmount -= userStake.amount;
        activeStakes[msg.sender]--;
        if (activeStakes[msg.sender] == 0) {
            activeStakers--;
        }

        emit StakeRemoved(msg.sender, _stakeID, userStake.amount, finalStakeReward);
    }

    /**
    * @notice Calculates the penalty for early unstaking
    * @param _stakeID The ID of the stake to get penalty
    * @return The penalty as a percentage of the reward
    * @dev 
    * - Penalizes early unstaking.
    * - No penalty if stake is completed or in the first hour of the stake.
    * - 70% penalty if unstaked within first 60 days.
    * - Linearly decreasing penalty based on completed stake afterwards.
    */
    function getStakePenalty(uint256 _stakeID) public view returns (uint256) {
        require(stakes[msg.sender][_stakeID].createdAt > 0, "This stake does not exist");
        Stake storage userStake = stakes[msg.sender][_stakeID];

        uint256 totalStakingDuration = userStake.endAt.sub(userStake.createdAt);
        uint256 completedStake = block.timestamp.sub(userStake.createdAt);

        if(block.timestamp < userStake.createdAt + 1 hours) {
            return 100;
        }

        if(block.timestamp > userStake.endAt) {
            return 100;
        }

        if(block.timestamp < userStake.createdAt + 60 days) {
            return 30;
        } else {
            return 30 + 70 * completedStake / totalStakingDuration;
        }
    }

    /**
    * @notice Calculates the bonus APY based on 'Bank Crash' events
    * @param _stakeID The ID of the stake for which the bonus APY is calculated
    * @return The bonus APY amount
    * @dev Checks the number of each type of 'Bank Crash' events that have occurred since the user's stake was created, and calculates the bonus APY
    */
    function getBonusAPY(uint _stakeID) public view returns (uint256) {
        require(stakes[msg.sender][_stakeID].createdAt > 0, "This stake does not exist");
        Stake storage userStake = stakes[msg.sender][_stakeID];

        uint256 bigBankCollapses    = bankCrashEvents.bigCrash    - userStake.memento.bigCrash;
        uint256 mediumBankCollapses = bankCrashEvents.mediumCrash - userStake.memento.mediumCrash;
        uint256 smallBankCollapses  = bankCrashEvents.smallCrash  - userStake.memento.smallCrash;

        return bigBankCollapses * 21 + mediumBankCollapses * 9 + smallBankCollapses * 2;
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
    * @notice Calculates the total reward for a stake, taking into account periodic halvings.
    * @param finalApy The combined Annual Percentage Yield (APY) of the stake (base + bonus).
    * @param userStake The stake for which the reward is calculated.
    * @return The total reward amount for the stake duration.
    * @dev 
    * - The reward calculation takes into account the periodic halving of the APY.
    * - The function works by breaking the stake duration into periods defined by the `halvingPeriod`. 
    *   For each period, it calculates the reward based on the current APY, and then reduces the APY for the next period.
    * - The function uses the `calculatePeriodicReward` to compute the reward for each period.
    * - The APY for a period will never exceed the `maximumAPY` of the stake.
    * - The reward calculation stops either when the stake ends or at the current block timestamp, whichever is earlier.
    * 
    * Requirements:
    * - The stake must have been created before calling this function.
    */
    function calculateReward(uint256 finalApy, Stake memory userStake) internal view returns (uint256) {
        uint256 periodStart = userStake.createdAt;
        uint256 halvingPeriod = 2 * 365 days;
        uint256 periods = periodStart.sub(stakingRewardHalveningStart).div(halvingPeriod);
        uint256 halvingPeriodStart = stakingRewardHalveningStart + (halvingPeriod * periods);
        uint256 totalReward = userStake.amount;
        uint256 maxApyInWad = userStake.maximumAPY.mul(1 ether).div(100);
        uint256 finalApyInWad = finalApy.mul(1 ether).div(100);
        uint256 periodDuration;
        uint256 reward;
        uint256 periodEnd;
        uint256 endTime = min(userStake.endAt, block.timestamp);

        while (periodStart < userStake.endAt) {
            periodStart = max(halvingPeriodStart, userStake.createdAt);
            periodEnd   = min(halvingPeriodStart + halvingPeriod, endTime);

            if (periodStart >= endTime) break;

            periodDuration = periodEnd.sub(periodStart);
            reward = calculatePeriodicReward(totalReward, periodDuration, periods, finalApyInWad, maxApyInWad);

            totalReward = totalReward.add(reward);

            halvingPeriodStart += halvingPeriod;
            periods++;
        }
        
        return totalReward - userStake.amount;
    }

    /**
    * @dev Calculates the reward for a single period
    * @param totalReward The principal amount for the period
    * @param periodDuration The duration of the period in seconds
    * @param periods The number of periods that have passed since stakingRewardHalveningStart
    * @param finalApyInWad The APY for the stake, in Wad format (baseAPY + bonusAPY)
    * @return The reward amount in wei for the given period
    */
    function calculatePeriodicReward(uint256 totalReward, uint256 periodDuration, uint256 periods, uint256 finalApyInWad, uint256 maxApyInWad) internal pure returns (uint256) {
        uint256 periodApyInWad = finalApyInWad.div(2 ** periods);
        periodApyInWad = min(periodApyInWad, maxApyInWad);
        uint256 interestRate = yearlyRateToRay(periodApyInWad);
        uint256 principalInRay = totalReward.mul(10 ** 27);
        uint256 finalAmount = accrueInterest(principalInRay, interestRate, periodDuration);
        uint256 reward = finalAmount.sub(principalInRay).div(10 ** 27);
        return reward;
    }

    function getStakes() external view returns (Stake[] memory) {
        Stake[] memory stakesArray = new Stake[](nextStakeID[msg.sender]);
        for (uint256 i = 0; i < nextStakeID[msg.sender]; i++) {
            stakesArray[i] = stakes[msg.sender][i];
        }
        return stakesArray;
    }
}
