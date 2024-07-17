// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { ERC2771Context } from "../lib/relay-context-contracts/contracts/vendor/ERC2771Context.sol";
import { Context } from "../lib/openzeppelin-contracts/contracts/utils/Context.sol";
import { SaleBase } from "./SaleBase.sol";
import "src/vendor/StructsLibrary.sol";
import "src/interfaces/INFTLotteryTicket.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/ILotteryV2.sol";

contract AuctionV2Base is SaleBase {
    function initialize(StructsLibrary.IAuctionV2BaseConfig memory config) public initializer {
        seller = config._seller;
        _transferOwnership(config._owner);
        numberOfTickets = config._ticketAmount;
        ticketPrice = config._ticketPrice;
        initialPrice = config._ticketPrice;
        usdcContractAddr = config._usdcContractAddr;
        nftContractAddr = config._nftContractAddr;
        multisigWalletAddress = config._multisigWalletAddress;
        auctionV1Addr = config._prevPhaseContractAddr;
    }

    struct Deposit {
        uint256 amount;
        uint256 statsAmount;
        uint256 timestamp;
        bool isWinner;
    }
    mapping(address => Deposit) public Deposits;
    mapping(address => bool) public operators;
    uint256 public initialPrice;
    address public auctionV1Addr;

    modifier onlyOperator() {
        // operator = seller or owner or specified address
        require(_msgSender() == seller || _msgSender() == owner() || operators[_msgSender()], "Only operator can call this function");
        _;
    }

    function isParticipant(address _participant) public view returns (bool) {
        for (uint i = 0; i < participants.length; i++) {
            if (participants[i] == _participant) {
                return true;
            }
        }
        return false;
    }

    function getDepositedAmount(address participant) external view override returns (uint256) {
        return Deposits[participant].amount;
    }

    function setOperator(address _operator, bool _flag) public onlyOwner {
        operators[_operator] = _flag;
    }

    function deposit(uint256 amount) public lotteryStarted {
        require(!isWinner(_msgSender()), "Winners cannot deposit");
        require(usdcContractAddr != address(0), "USDC contract address not set");
        require(amount >= initialPrice, "Insufficient funds sent");
        require(IERC20(usdcContractAddr).allowance(_msgSender(), address(this)) >= amount, "Insufficient allowance");

        IERC20(usdcContractAddr).transferFrom(_msgSender(), address(this), amount);
        
        if(isParticipant(_msgSender())) {
            Deposits[_msgSender()].amount += amount;
            Deposits[_msgSender()].statsAmount += amount;
        } else {
            Deposits[_msgSender()] = Deposit(amount, amount, block.timestamp, false);
            participants.push(_msgSender());
        }
        emit BuyerDeposited(_msgSender(), amount);
    }

    function setWinner(address _winner) internal override onlySeller {
        winners[_winner] = true;
        winnerAddresses.push(_winner);
        Deposits[_winner].isWinner = true;
        emit WinnerSelected(_winner);
    }

    function buyerWithdraw() public override lotteryEnded {
        require(!winners[_msgSender()], "Winners cannot withdraw");
        uint256 amount = Deposits[_msgSender()].amount;
        require(amount > 0, "No funds to withdraw");
        Deposits[_msgSender()].amount = 0;
        IERC20(usdcContractAddr).transfer(_msgSender(), amount);
        emit BuyerWithdrew(_msgSender(), amount);
    }

    // sort participants by deposit amount DESC
    function sortDepositsDesc() public onlySeller {
        for (uint256 i = 0; i < participants.length; i++) {
            for (uint256 j = i + 1; j < participants.length; j++) {
                if (
                    Deposits[participants[i]].amount < Deposits[participants[j]].amount ||
                    (Deposits[participants[i]].amount == Deposits[participants[j]].amount && Deposits[participants[i]].timestamp > Deposits[participants[j]].timestamp)
                ) {
                    address temp = participants[i];
                    participants[i] = participants[j];
                    participants[j] = temp;
                }
            }
        }
    }

    function transferDepositsBack() internal override onlySeller lotteryEnded {
        uint256 participantsLength = participants.length;
        address[] memory participantsCopy = new address[](participantsLength);
        for (uint256 i = 0; i < participantsLength; i++) {
            participantsCopy[i] = participants[i];
        }
        for (uint256 i = 0; i < participantsLength; i++) {
            address participant = participantsCopy[i];
            uint256 depositAmount = Deposits[participant].amount;
            Deposits[participant].amount = 0;

            if (isWinner(participant)) {
                totalAmountForSeller += depositAmount;
            } else {
                IERC20(usdcContractAddr).transfer(participant, depositAmount);
            }
        }
        sellerWithdraw();
        emit DepositsReturned(participantsLength);
    }

    function selectWinners() external onlySeller {
        require(numberOfTickets > 0, "No tickets left to allocate");

        if(numberOfTickets >= participants.length) {
            // less demand than supply, no need for lottery. Everybody wins!
            for (uint256 i = 0; i < participants.length; i++) {
                address selectedWinner = participants[i];

                if (!isWinner(selectedWinner)) {
                    setWinner(selectedWinner);
                    emit WinnerSelected(selectedWinner);
                }
            }
        } else {
            sortDepositsDesc();
            uint256 lowestWinDeposit = Deposits[participants[numberOfTickets - 1]].amount;

            // take the first n winners
            for (uint256 i = 0; i < numberOfTickets; i++) {
                if(Deposits[participants[i]].amount >= lowestWinDeposit) {
                  address selectedWinner = participants[i];

                  if (!isWinner(selectedWinner)) {
                      setWinner(selectedWinner);
                      emit WinnerSelected(selectedWinner);
                  }
                }
            }
        }
        lotteryState = LotteryState.ENDED;
        transferDepositsBack();
        emit LotteryEnded();
    }

    function mintMyNFT() public hasNotMinted hasWon {
        require(numberOfTickets > 0, "No tickets left to allocate");
        hasMinted[_msgSender()] = true;
        numberOfTickets--;
        INFTLotteryTicket(nftContractAddr).lotteryMint(_msgSender());
    }

    function transferDeposit(address _participant, uint256 _amount) public {
        require(auctionV1Addr == _msgSender(), "Only whitelisted may call this function");

        if(isParticipant(_participant)) {
            Deposits[_participant].amount += _amount;
        } else {
            Deposits[_participant] = Deposit(_amount, _amount, block.timestamp, false);
            participants.push(_participant);
        }
    }    
}
