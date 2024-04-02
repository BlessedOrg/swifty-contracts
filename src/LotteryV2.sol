// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { GelatoVRFConsumerBase } from "../lib/vrf-contracts/contracts/GelatoVRFConsumerBase.sol";
import "src/interfaces/INFTLotteryTicket.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/IAuctionV1.sol";

contract LotteryV2 is GelatoVRFConsumerBase, Ownable {
    constructor(address _seller, address _operatorAddr)
    Ownable(msg.sender) {
        seller = _seller;
        operatorAddr = _operatorAddr;
    }

    enum LotteryState {
      NOT_STARTED,
      ACTIVE,
      ENDED
    }

    LotteryState public lotteryState;

    address public multisigWalletAddress;
    address public seller;
    address public immutable operatorAddr;

    uint256 public minimumDepositAmount;
    uint256 public numberOfTickets;
    uint256 public maxMints;
    uint256 public mintCount;
    uint256 public randomNumber;
    mapping(address => bool) public hasMinted;

    mapping(address => uint256) public deposits;
    mapping(address => bool) public winners;
    address[] public winnerAddresses;
    address[] private participants;

    address public nftContractAddr;
    address public usdcContractAddr;
    address public lotteryV1Addr;

    uint256 public finishAt;

    mapping(address => uint256) public rolledNumbers;
    uint256 public rollPrice;
    uint256 public rollTolerance = 0;

    event LotteryStarted();
    event WinnerSelected(address indexed winner);
    event LotteryEnded();
    event RandomRequested(address indexed requester);
    event RandomFullfiled(address indexed requester, uint256 number);   

    modifier onlySeller() {
        require(msg.sender == seller, "Only seller can call this function");
        _;
    }

    modifier lotteryNotStarted() {
        require(lotteryState == LotteryState.NOT_STARTED, "Lottery is in active state");
        _;
    }

    modifier lotteryStarted() {
        require(lotteryState == LotteryState.ACTIVE, "Lottery is not active");
        _;
    }

    modifier lotteryEnded() {
        require(lotteryState == LotteryState.ENDED, "Lottery is not ended yet");
        _;
    }

    modifier hasNotMinted() {
        require(!hasMinted[msg.sender], "NFT already minted");
        _;
    }

    modifier whenLotteryNotActive() {
        require(lotteryState != LotteryState.ACTIVE, "Lottery is currently active");
        _;
    }

    function _operator() internal view override returns (address) {
        return operatorAddr;
    } 

    function requestRandomness(bytes memory) external {
        _requestRandomness(abi.encode(msg.sender));
        emit RandomRequested(msg.sender);
    }

    function _fulfillRandomness(uint256 randomness, uint256, bytes memory extraData) internal override {
        address requestedBy = abi.decode(extraData, (address));
        
        if(requestedBy == seller) {
            rolledNumbers[requestedBy] = randomness;
        } else {
            randomNumber = randomness;
        }
        emit RandomFullfiled(requestedBy, randomness);
    }           

    function deposit(uint256 amount) public whenLotteryNotActive {
        require(finishAt > block.timestamp, "Deposits are not possible anymore");
        require(usdcContractAddr != address(0), "USDC contract address not set");
        require(amount > 0, "No funds sent");
        require(
            IERC20(usdcContractAddr).allowance(msg.sender, address(this)) >= amount, 
            "Insufficient allowance"
        );

        IERC20(usdcContractAddr).transferFrom(msg.sender, address(this), amount);
        
        if(deposits[msg.sender] == 0) {
            participants.push(msg.sender);
        }
        deposits[msg.sender] += amount;

        if(rolledNumbers[msg.sender] == 0) {
            _requestRandomness(abi.encode(msg.sender));
            emit RandomRequested(msg.sender);
        }
    }

    function getParticipants() public view returns (address[] memory) {
        return participants;
    }

    function setMultisigWalletAddress(address _multisigWalletAddress) public onlyOwner {
        multisigWalletAddress = _multisigWalletAddress;
    }

    function setNftContractAddr(address _nftContractAddr) public onlyOwner {
        nftContractAddr = _nftContractAddr;
    }    

    function changeLotteryState(LotteryState _newState) public onlySeller {
        lotteryState = _newState;
    }

    function isWinner(address _participant) public view returns (bool) {
        return winners[_participant];
    }

    function getWinners() public view returns (address[] memory) {
        return winnerAddresses;
    }

    function setWinner(address _winner) public onlySeller {
        winners[_winner] = true;
        winnerAddresses.push(_winner);
    }

    function buyerWithdraw() public whenLotteryNotActive {
        require(!winners[msg.sender], "Winners cannot withdraw");

        uint256 amount = deposits[msg.sender];
        require(amount > 0, "No funds to withdraw");

        deposits[msg.sender] = 0;
        IERC20(usdcContractAddr).transfer(msg.sender, amount);
    }

    function sellerWithdraw() public onlySeller() {
        require(lotteryState == LotteryState.ENDED, "Lottery not ended");

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < winnerAddresses.length; i++) {
            address winner = winnerAddresses[i];
            totalAmount += deposits[winner];
            deposits[winner] = 0; // Prevent double withdrawal
        }

        uint256 protocolTax = (totalAmount * 5) / 100; // 5% tax
        uint256 amountToSeller = totalAmount - protocolTax;

        IERC20(usdcContractAddr).transfer(multisigWalletAddress, protocolTax);
        IERC20(usdcContractAddr).transfer(seller, amountToSeller);
    }

    function getRandomNumber() public view returns (uint256) {
        // Replace with actual VRF result
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender))); 
    }

    function setMinimumDepositAmount(uint256 _amount) public onlySeller {
        minimumDepositAmount = _amount;
    }

    function setNumberOfTickets(uint256 _numberOfTickets) public onlySeller {
        require(_numberOfTickets > 0, "Number of tickets must be greater than zero");
        numberOfTickets = _numberOfTickets;
        maxMints = _numberOfTickets;
        mintCount = 0;
    }

    function startLottery() public onlySeller lotteryNotStarted {
        changeLotteryState(LotteryState.ACTIVE);
    }

    function endLottery() public onlySeller {
        changeLotteryState(LotteryState.ENDED);
        // Additional logic for ending the lottery
        // Process winners, mint NFT tickets, etc.
    }

    function getDepositedAmount(address participant) external view returns (uint256) {
        return deposits[participant];
    }

    function mintMyNFT() public hasNotMinted lotteryEnded {
        require(isWinner(msg.sender), "Caller is not a winner");
        require(mintCount < maxMints, "No more mints available"); 

        hasMinted[msg.sender] = true;
        INFTLotteryTicket(nftContractAddr).lotteryMint(msg.sender);
        mintCount++;
    }

    function setUsdcContractAddr(address _usdcContractAddr) public onlyOwner {
        usdcContractAddr = _usdcContractAddr;
    }

    function setRandomNumber() public onlySeller() {
        require(randomNumber == 0, "Random number already set");

        randomNumber = getRandomNumber();
    }

    function setRollPrice(uint256 _rollPrice) public onlySeller() {
        rollPrice = _rollPrice;
    }

    function setRollTolerance(uint256 _tolerance) public onlySeller() {
        rollTolerance = _tolerance;
    }

    function roll() public {
        require(finishAt > block.timestamp, "Rolling is not possible anymore");
        require(rollPrice > 0, "No roll price set");
        require(deposits[msg.sender] >= rollPrice + minimumDepositAmount, "Insufficient funds");

        deposits[msg.sender] -= rollPrice;
        deposits[seller] += rollPrice;

        rolledNumbers[msg.sender] = getRandomNumber();
    }

    function isClaimable(address _participant) public view returns (bool) {
      if(deposits[_participant] >= minimumDepositAmount && randomNumber + rollTolerance >= rolledNumbers[_participant] && randomNumber - rollTolerance <= rolledNumbers[_participant]) {
        return true;
      }
      return false;
    }

    function claimNumber(address _participant) public {
      if(isClaimable(_participant)) {
        winners[_participant] = true;
        winnerAddresses.push(_participant);
        emit WinnerSelected(_participant);
      } else {
        revert("Participant is not claimable");
      }
    }

    function setLotteryV1Addr(address _lotteryV1Addr) public onlySeller {
        lotteryV1Addr = _lotteryV1Addr;
    }

    function setFinishAt(uint _finishAt) public onlySeller {
        finishAt = _finishAt;
    }

    function transferDeposit(address _participant, uint256 _amount) public {
        require(lotteryV1Addr == msg.sender, "Only whitelisted may call this function");

        if(deposits[_participant] == 0) {
            participants.push(_participant);
        }
        deposits[_participant] += _amount;

        if(rolledNumbers[_participant] == 0) {
            rolledNumbers[_participant] = getRandomNumber();
        }
    }

    function transferNonWinnerDeposits(address auctionV1addr) public onlySeller {
        for(uint256 i = 0; i < participants.length; i++) {
            if(!isWinner(participants[i])) {
              uint256 currentDeposit = deposits[participants[i]];
              deposits[participants[i]] = 0;
              IERC20(usdcContractAddr).transfer(auctionV1addr, currentDeposit);
              IAuctionV1(auctionV1addr).transferDeposit(participants[i], currentDeposit);
            }
        }
    }
}
