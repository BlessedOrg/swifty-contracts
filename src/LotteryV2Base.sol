// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { GelatoVRFConsumerBase } from "../lib/vrf-contracts/contracts/GelatoVRFConsumerBase.sol";
import { ERC2771Context } from "../lib/relay-context-contracts/contracts/vendor/ERC2771Context.sol";
import { Context } from "../lib/openzeppelin-contracts/contracts/utils/Context.sol";
import { SaleBase } from "./SaleBase.sol";
import "src/vendor/StructsLibrary.sol";
import "src/interfaces/INFTLotteryTicket.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/IAuctionV1.sol";
import "src/interfaces/ILotteryV1.sol";

contract LotteryV2Base is SaleBase, GelatoVRFConsumerBase {
    function initialize(StructsLibrary.ILotteryV2BaseConfig memory config) public initializer {
        seller = config._blessedOperator;
        operatorAddr = config._gelatoVrfOperator;
        _transferOwnership(config._owner);
        numberOfTickets = config._ticketAmount;
        ticketPrice = config._ticketPrice;
        rollPrice = config._rollPrice;
        rollTolerance = config._rollTolerance;
        usdcContractAddr = config._usdcContractAddr;
        nftContractAddr = config._nftContractAddr;
        multisigWalletAddress = config._multisigWalletAddress;
        lotteryV1Addr = config._prevPhaseContractAddr;
    }

    address public operatorAddr;
    uint256 public randomNumber;
    address public lotteryV1Addr;
    mapping(address => uint256) public rolledNumbers;
    uint256 public rollPrice;
    uint256 public rollTolerance;
    uint256 public constant MAX_RANDOM = 1e14;

    event RandomRequested(address indexed requester);
    event RandomFulfilled(address indexed requester, uint256 number);

    modifier hasNotWonInLotteryV1(address participant) {
        require(!ILotteryV1(lotteryV1Addr).isWinner(participant), "Participant has already won in LotteryV1");
        _;
    }

    function _operator() internal view override returns (address) {
        return operatorAddr;
    }

    function requestRandomness() external onlySeller {
        _requestRandomness(abi.encode(_msgSender()));
        emit RandomRequested(_msgSender());
    }

    function _fulfillRandomness(uint256 randomness, uint256, bytes memory extraData) internal override {
        address requestedBy = abi.decode(extraData, (address));
        uint256 _randomNumber =  randomness % MAX_RANDOM;

        if (requestedBy == seller) {
            randomNumber = _randomNumber;
        } else {
            rolledNumbers[requestedBy] = _randomNumber;
            claimNumber(requestedBy);
        }
        emit RandomFulfilled(requestedBy, _randomNumber);
    }

    function deposit(uint256 amount) public lotteryStarted hasNotWonInLotteryV1(_msgSender()) {
        require(usdcContractAddr != address(0), "USDC contract address not set");
        require(amount >= rollPrice, "Not enough funds sent");
        require(IERC20(usdcContractAddr).allowance(_msgSender(), address(this)) >= amount, "Insufficient allowance");

        IERC20(usdcContractAddr).transferFrom(_msgSender(), address(this), amount);

        if (deposits[_msgSender()] == 0) {
            participants.push(_msgSender());

            if (rolledNumbers[_msgSender()] == 0) {
                _requestRandomness(abi.encode(_msgSender()));
                emit RandomRequested(_msgSender());
            }
        }
        deposits[_msgSender()] += amount;
        emit BuyerDeposited(_msgSender(), amount);
    }

    function roll() public lotteryStarted {
        require(rollPrice > 0, "No roll price set");
        require(deposits[_msgSender()] >= rollPrice + ticketPrice, "Insufficient funds");

        deposits[_msgSender()] -= rollPrice;
        deposits[seller] += rollPrice;

        _requestRandomness(abi.encode(_msgSender()));
    }

    function isClaimable(address _participant) public view returns (bool) {
        uint256 tolerance = (MAX_RANDOM * rollTolerance) / 100;
        uint256 lowerLimit = (randomNumber >= tolerance) ? randomNumber - tolerance : 0;
        uint256 upperLimit = (randomNumber + tolerance <= MAX_RANDOM) ? randomNumber + tolerance : MAX_RANDOM;

        uint256 participantNumber = rolledNumbers[_participant];

        bool isWithinTolerance = (participantNumber >= lowerLimit && participantNumber <= upperLimit);

        return (deposits[_participant] >= ticketPrice && isWithinTolerance);
    }

    function claimNumber(address _participant) public returns (bool) {
        if (isClaimable(_participant) && !winners[_participant]) {
            winners[_participant] = true;
            winnerAddresses.push(_participant);
            emit WinnerSelected(_participant);
            return true;
        } else {
            return false;
        }
    }

    function transferDeposit(address _participant, uint256 _amount) public {
        require(lotteryV1Addr == _msgSender(), "Only whitelisted may call this function");

        if (deposits[_participant] == 0) {
            participants.push(_participant);

            if (rolledNumbers[_participant] == 0) {
                _requestRandomness(abi.encode(_participant));
            }
        }
        deposits[_participant] += _amount;
    }

    function transferNonWinnerDeposits(address auctionV1addr) public onlySeller {
        for (uint256 i = 0; i < participants.length; i++) {
            if (!isWinner(participants[i])) {
                uint256 currentDeposit = deposits[participants[i]];
                deposits[participants[i]] = 0;
                IERC20(usdcContractAddr).transfer(auctionV1addr, currentDeposit);
                IAuctionV1(auctionV1addr).transferDeposit(participants[i], currentDeposit);
            }
        }
    }

    function mintMyNFT() public hasNotMinted hasWon hasNotWonInLotteryV1(_msgSender()) {
        hasMinted[_msgSender()] = true;
        deposits[_msgSender()] = 0;
        INFTLotteryTicket(nftContractAddr).lotteryMint(_msgSender());
    }

    function endLottery() public override onlySeller {
        changeLotteryState(LotteryState.ENDED);
        transferDepositsBack();
        emit LotteryEnded();
    }
}
