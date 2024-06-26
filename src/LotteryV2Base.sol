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
    function initialize(StructsLibrary.ILotteryBaseConfig memory config) public {
        require(initialized == false, "Already initialized");
        seller = config._blessedOperator;
        operatorAddr = config._gelatoVrfOperator;
        _transferOwnership(config._owner);
        numberOfTickets = config._ticketAmount;
        minimumDepositAmount = config._ticketPrice;
        usdcContractAddr = config._usdcContractAddr;
        multisigWalletAddress = config._multisigWalletAddress;
        lotteryV1Addr = config._prevPhaseContractAddr;

        initialized = true;
    }

    bool public initialized = false;

    address public operatorAddr;
    uint256 public maxMints;
    uint256 public mintCount;
    uint256 public randomNumber;
    address public lotteryV1Addr;
    mapping(address => uint256) public rolledNumbers;
    uint256 public rollPrice;
    uint256 public rollTolerance = 0;

    event RandomRequested(address indexed requester);
    event RandomFulfilled(address indexed requester, uint256 number);

    modifier hasNotWonInLotteryV1(address participant) {
        require(!ILotteryV1(lotteryV1Addr).isWinner(participant), "Participant has already won in LotteryV1");
        _;
    }

    function _operator() internal view override returns (address) {
        return operatorAddr;
    }

    function setRandomNumber() public onlySeller() {
        require(randomNumber == 0, "Random number already set");
        randomNumber = getRandomNumber();
    }

    function getRandomNumber() public view returns (uint256) {
        // it's used as a mockup for tests
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, _msgSender())));
    }

    function requestRandomness() external onlySeller {
        _requestRandomness(abi.encode(_msgSender()));
        emit RandomRequested(_msgSender());
    }

    function _fulfillRandomness(uint256 randomness, uint256, bytes memory extraData) internal override {
        address requestedBy = abi.decode(extraData, (address));
        uint256 _randomNumber = randomness % 100_000_000_000_000;

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
    }

    function setNumberOfTickets(uint256 _numberOfTickets) public override onlySeller {
        require(_numberOfTickets > 0, "Number of tickets must be greater than zero");
        numberOfTickets = _numberOfTickets;
        maxMints = _numberOfTickets;
        mintCount = 0;
    }

    function mintMyNFT() public hasNotMinted hasNotWonInLotteryV1(_msgSender()) {
        require(isWinner(_msgSender()), "Caller is not a winner");
        hasMinted[_msgSender()] = true;
        uint256 remainingBalance = deposits[_msgSender()] - minimumDepositAmount;
        if (remainingBalance > 0) {
            IERC20(usdcContractAddr).transfer(_msgSender(), remainingBalance);
        }
        deposits[_msgSender()] = 0;
        INFTLotteryTicket(nftContractAddr).lotteryMint(_msgSender());
    }

    function setRollPrice(uint256 _rollPrice) public onlySeller() {
        rollPrice = _rollPrice;
    }

    function setRollTolerance(uint256 _tolerance) public onlySeller() {
        require(_tolerance >= 1 && _tolerance <= 99, "Tolerance percentage must be between 1 and 99");
        rollTolerance = _tolerance;
    }

    function roll() public lotteryStarted {
        require(rollPrice > 0, "No roll price set");
        require(deposits[_msgSender()] >= rollPrice + minimumDepositAmount, "Insufficient funds");

        deposits[_msgSender()] -= rollPrice;
        deposits[seller] += rollPrice;

        _requestRandomness(abi.encode(_msgSender()));
    }

    function isClaimable(address _participant) public view returns (bool) {
        uint256 lowerLimit = rolledNumbers[_participant] - ((rolledNumbers[_participant] * rollTolerance / 100));
        uint256 upperLimit = rolledNumbers[_participant] + ((rolledNumbers[_participant] * rollTolerance / 100));
        bool isWithinTolerance = (randomNumber >= lowerLimit) && (randomNumber <= upperLimit);

        if (deposits[_participant] >= minimumDepositAmount && isWithinTolerance) {
            return true;
        }
        return false;
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
}
