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
    function initialize(StructsLibrary.IAuctionV2BaseConfig memory config) public {
        require(initialized == false, "Already initialized");
        seller = config._seller;
        _transferOwnership(config._owner);
        numberOfTickets = config._ticketAmount;
        minimumDepositAmount = config._ticketPrice;
        initialPrice = config._ticketPrice;
        usdcContractAddr = config._usdcContractAddr;
        nftContractAddr = config._nftContractAddr;
        multisigWalletAddress = config._multisigWalletAddress;
        auctionV1Addr = config._prevPhaseContractAddr;

        initialized = true;
    }

    struct Deposit {
      uint256 amount;
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

    function deposit(uint256 amount) public lotteryStarted {
        require(!isWinner(_msgSender()), "Winners cannot deposit");
        require(usdcContractAddr != address(0), "USDC contract address not set");
        require(amount >= initialPrice, "Insufficient funds sent");
        require(IERC20(usdcContractAddr).allowance(_msgSender(), address(this)) >= amount, "Insufficient allowance");

        IERC20(usdcContractAddr).transferFrom(_msgSender(), address(this), amount);
        
        if(isParticipant(_msgSender())) {
            Deposits[_msgSender()].amount += amount;
        } else {
            Deposits[_msgSender()] = Deposit(amount, block.timestamp, false);
            participants.push(_msgSender());
        }
        emit BuyerDeposited(_msgSender(), amount);
    }

    function setOperator(address _operator, bool _flag) public onlyOwner {
        operators[_operator] = _flag;
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

    function sellerWithdraw() public override onlySeller() {
        require(lotteryState == LotteryState.ENDED, "Lottery not ended");

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < winnerAddresses.length; i++) {
            address winner = winnerAddresses[i];
            totalAmount += Deposits[winner].amount;
            Deposits[winner].amount = 0; // Prevent double withdrawal
        }

        uint256 protocolTax = (totalAmount * 5) / 100; // 5% tax
        uint256 amountToSeller = totalAmount - protocolTax;

        IERC20(usdcContractAddr).transfer(multisigWalletAddress, protocolTax);
        IERC20(usdcContractAddr).transfer(seller, amountToSeller);
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
        emit LotteryEnded();
    }

    function setInitPrice(uint256 _amount) public onlySeller {
      if(initialPrice == 0) {
        initialPrice = _amount;
      }
    }

    function getDepositedAmount(address participant) external view override returns (uint256) {
        return Deposits[participant].amount;
    }

    function mintMyNFT() public hasNotMinted {
        require(numberOfTickets > 0, "No tickets left to allocate");
        require(isWinner(_msgSender()), "Caller is not a winner");
        hasMinted[_msgSender()] = true;
        uint256 remainingBalance = Deposits[_msgSender()].amount - minimumDepositAmount;
        if (remainingBalance > 0) {
            IERC20(usdcContractAddr).transfer(_msgSender(), remainingBalance);
        }
        Deposits[_msgSender()].amount = 0;
        numberOfTickets--;
        INFTLotteryTicket(nftContractAddr).lotteryMint(_msgSender());
    }

    function transferDeposit(address _participant, uint256 _amount) public {
        require(auctionV1Addr == _msgSender(), "Only whitelisted may call this function");

        if(isParticipant(_participant)) {
            Deposits[_participant].amount += _amount;
        } else {
            Deposits[_participant] = Deposit(_amount, block.timestamp, false);
            participants.push(_participant);
        }
    }    
}
