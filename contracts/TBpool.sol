// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {TA} from "./TA.sol";
import {TB} from "./TB.sol";
import "hardhat/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract TBpool is ERC1155Holder {
    //===============Variables=============
    TB TBcontract;

    //===============Functions=============
    constructor(address payable _TBaddress) {
        TBcontract = TB(_TBaddress);
    }

    mapping(address => PoolStaker) public staker;
    struct PoolStaker {
        uint256 amount; // The NFT tokens quantity the user has staked.
        uint256 rewards; // The reward tokens quantity the user can harvest
        uint256 rewardDebt; // The amount relative to accumulatedRewardsPerShare the user can't get as reward
    }

    mapping(address => mapping(uint256 => uint256)) public depositsMade;

    // TBpool variables
    uint256 public tokensStaked; // Total NFT tokens staked
    uint256 public lastInflow; // Last block number the user had their rewards calculated
    uint256 public accumulatedRewardsPerShare; // Accumulated rewards per share times REWARDS_PRECISION

    function stakeNFT(uint256 _tbID, uint256 _quantity) external {
        require(TBcontract.balanceOf(msg.sender, _tbID) >= _quantity, "User does not own enough tokens");

        // Pay rewards
        harvestRewards();

        // Update current staker
        staker[msg.sender].amount = staker[msg.sender].amount + _quantity;
        staker[msg.sender].rewardDebt = (staker[msg.sender].amount * accumulatedRewardsPerShare);

        // Update pool
        tokensStaked += _quantity;

        // Stake NFTs
        depositsMade[msg.sender][_tbID] += _quantity;
        TBcontract.safeTransferFrom(msg.sender, address(this), _tbID, _quantity, "");
    }

    function harvestRewards() public {
        uint256 rewardsToHarvest = (staker[msg.sender].amount * accumulatedRewardsPerShare) -
            staker[msg.sender].rewardDebt;

        if (rewardsToHarvest == 0) {
            staker[msg.sender].rewardDebt = (staker[msg.sender].amount * accumulatedRewardsPerShare);
            return;
        }

        staker[msg.sender].rewards = 0;
        staker[msg.sender].rewardDebt = (staker[msg.sender].amount * accumulatedRewardsPerShare);
        _sendViaCall(payable(msg.sender), rewardsToHarvest);
    }

    function withdraw(uint256[] memory _tbID, uint256[] memory _quantity) public {
        require(staker[msg.sender].amount > 0, "Withdraw amount can't be zero");

        // Check if all tbIDs and quantities were supplied correctly
        uint256 nftSum;
        for (uint256 j = 0; j < _tbID.length; j++) {
            nftSum += depositsMade[msg.sender][_tbID[j]];
            require(_quantity[j] == depositsMade[msg.sender][_tbID[j]], "Quantity was wrongly introduced");
        }
        require(nftSum == staker[msg.sender].amount, "User has not introduced all IDs that he/she has staked");

        // Pay rewards
        harvestRewards();

        // Update pool
        tokensStaked -= staker[msg.sender].amount;

        // Update current staker
        staker[msg.sender].amount = 0;
        staker[msg.sender].rewardDebt = (staker[msg.sender].amount * accumulatedRewardsPerShare);
        for (uint256 i = 0; i < _tbID.length; i++) {
            depositsMade[msg.sender][_tbID[i]] = 0;
        }

        // Unstake NFTs
        TBcontract.safeBatchTransferFrom(address(this), msg.sender, _tbID, _quantity, "");
    }

    function updatePoolRewards(uint256 _inflow) private {
        if (tokensStaked == 0) {
            lastInflow += 1;
            return;
        }
        accumulatedRewardsPerShare = accumulatedRewardsPerShare + (_inflow / tokensStaked);
        lastInflow += 1;
    }

    function _sendViaCall(address payable _to, uint256 _value) private {
        (bool sent, ) = _to.call{value: _value}("");
        require(sent, "Failed to send Ether");
    }

    receive() external payable {
        updatePoolRewards(msg.value);
    }
}
