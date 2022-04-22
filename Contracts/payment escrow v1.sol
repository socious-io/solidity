// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import './ownership/ownable.sol';

contract PaymentEscrow is Ownable {

    address payable private _owner;
    uint private _providerFee = 10; // Service Providers Fee
    uint private _orgFee = 3;   // Organizations Fee
    
    //Used to store organizations's transactions and for Organizations to interact with his transactions. (Such as releasing funds to hired people)
    struct EscrowData {
        address serviceProvider;  // Contracted person that provides the services

        uint projectId;            // Identifier for the project

        uint netAmmount;           // Full value (in Wei) of the transaction
        uint organizationFee;          // What user will recieve after fees are discounted
        uint providerFee;

        bool isHired;           // Step 1: 'Hired' (In progress) - The Escrow is created and both parts agree to the job conditions
        bool isCompleted;       // Step 2: 'Completed' - The Provider indicates that he is done with his job. Awaiting approval from Contractor
        bool isFinished;        // Step 3: 'Finished' - The project is agreed as successfully completed by both sides
        bool isReviewed;        // Step (2.1) 'Review' - There has been an intervention from escrow agent and has yet to deliver a veredict
        bool isCanceled;        // Step (3.1): 'Canceled' - If the conditions are not met. The funds are returned to the organization aka. buyer

        bytes32 notes;            //Notes for service provider
    }

    struct TransactionData {                        
        // History of transaction for service providers
        address organizationUser;    // Contractor who is making payment
        uint projectId;               // Project identifier
        uint transactionAmmount;
        uint transactionNumber;      // Transaction number on OrganizationHistory
    }
    
    // Each organization then contain an array of their transactions
    mapping(address => EscrowData[]) public organizationsHistory;

    // Registry for providers and escrow agent
    mapping(address => TransactionData[]) public providersHistory;        

    event ProviderNotification(address _providerUser, uint _transactionIndex);
    event OrganizationApproval(address _organizationUser, uint _escrowIndex);

    event DecisionNotification(address _organizationUser, address _providerUser, uint _escrowIndex);

    constructor () {
        address msgSender = _msgSender();
        _owner = payable(msgSender); // Set the contract creator
        emit OwnershipTransferred(address(0), msgSender);
    }

    function getProviderFee() public view returns(uint) {
        return _providerFee;
    }

    function getOrgFee() public view returns(uint) {
        return _orgFee;
    }

    function _setProviderFee(uint _newFee) private {
        require (_newFee != getProviderFee());
        _providerFee = _newFee;
    }

    function _setProviderFee(uint newFee) public onlyOwner {
        _setProviderFee(newFee);
    }

    function _setOrgFee(uint _newFee) private {
        require (_newFee != getOrgFee());
        _orgFee = _newFee;
    }

    function setOrgFee(uint newFee) public onlyOwner {
        _setOrgFee(newFee);
    }
     
    function newEscrow(address _providerAddress, uint _projectId, bytes32 _notes) public payable returns(bool) {
        // The organization will create the Escrow after negotiations with the User provider and will 
        // contain the necessary information regarding their aggrement. This is definitory and should be done
        // only after both parties are all right with the contract
        require(msg.value > 0 && msg.sender.balance >= msg.value && msg.sender != _providerAddress);
    
        //Store escrow details in memory
        EscrowData memory currentEscrow;
        TransactionData memory currentTransaction;
        
        currentEscrow.serviceProvider = _providerAddress;
        currentEscrow.projectId = _projectId;
        
        // Fee calculation
        uint organizationFee_ = (msg.value / 100) * getOrgFee();
        uint providerFee_ = (msg.value / 100) * getProviderFee();
        uint totalFees = organizationFee_ + providerFee_;
        uint transactionFunds = msg.value - totalFees;

        currentEscrow.isHired = true;
        //These default to false, no need to set them again
        /* currentEscrow.isCompleted = false;
           currentEscrow.isFinished = false;
           currentEscrow.isReviewed = false;
           currentEscrow.isCanceled = false;  */ 

        currentEscrow.netAmmount = transactionFunds;
        currentEscrow.organizationFee = organizationFee_;
        currentEscrow.providerFee = providerFee_;
        currentEscrow.notes = _notes;

        // Links this transaction to seller list of transactions
        currentTransaction.organizationUser = msg.sender;
        currentTransaction.projectId = _projectId;
        currentTransaction.transactionAmmount = msg.value;
        currentTransaction.transactionNumber = organizationsHistory[msg.sender].length;

        // Treasury transfer
        (bool vaultFunding,) = _owner.call{value: msg.value}("");
        require(vaultFunding, "Failed to secure the funds");

        // Save data to blockchain storage
        providersHistory[_providerAddress].push(currentTransaction);
        organizationsHistory[msg.sender].push(currentEscrow);
        
        return true;
    }

    function getOrganizationHistory(address _organizationAddress) public view returns(EscrowData[] memory) {

        EscrowData[] memory results;

        for (uint i = 0; i < organizationsHistory[_organizationAddress].length; i++) {
            results[i] = organizationsHistory[_organizationAddress][i];
        }
        
        return results;
    }
                
    function getProvidersHistory(address _providerAddress, bool flagOrganizationU, bool flagProject, bool flagTransactionA, bool flagTransactionN) public view returns (address[] memory, uint[] memory, uint[] memory, uint[] memory) {     
        address[] memory organizationUsers_;
        uint[] memory projectIds_;
        uint[] memory transactionAmmounts_;
        uint[] memory transactionsNumbers_;

        for (uint i = 0; i < providersHistory[_providerAddress].length; i++) {
            if (flagOrganizationU) {
                organizationUsers_[i] = providersHistory[_providerAddress][i].organizationUser;
            }
            
            if (flagProject) {
                projectIds_[i] = providersHistory[_providerAddress][i].projectId;
            }

            if (flagTransactionA) {
                transactionAmmounts_[i] = providersHistory[_providerAddress][i].transactionAmmount;
            }

            if (flagTransactionN) {
                transactionsNumbers_[i] = providersHistory[_providerAddress][i].transactionNumber;
            }
        }
        return (organizationUsers_, projectIds_, transactionAmmounts_, transactionsNumbers_);
    }

    function getTransactionNumber(address _organizationAddress, address _providerAddress, uint _projectId, uint _transactionAmmount) public view returns(int) {
        (address[] memory organizationArray, uint[] memory projectArray, uint[] memory txArray, uint[] memory tNumArray) = getProvidersHistory(_providerAddress, true, true, true, true);

        int targetTransaction_ = -1; // This will help us identify and filter the EscrowData

        for (uint i = 0; i < providersHistory[_providerAddress].length; i++){
            if (organizationArray[i] == _organizationAddress && projectArray[i] == _projectId && txArray[i] == _transactionAmmount) {
                targetTransaction_ = int(tNumArray[i]);
            }
        }

        return int(targetTransaction_);
    }

    function getSpecificEscrow(address organizationAddress_, address providerAddress_, uint projectId_, uint transactionAmmount_) public view returns(EscrowData memory) {
        int targetTransaction = getTransactionNumber(organizationAddress_, providerAddress_, projectId_, transactionAmmount_);

        if (targetTransaction >= 0) {
            return organizationsHistory[organizationAddress_][uint(targetTransaction)];
        } else {
            return EscrowData(address(0), 0, 0, 0, 0, false, false, false, false, false, bytes32(bytes("")));
        }
    }

    function checkStatus(address _organizationAddress, uint _escrowIndex) internal view returns (uint8) {
        uint8 status;
        
        if (organizationsHistory[_organizationAddress][_escrowIndex].isHired) {
            status = 1; // Hired and/or In Progress
        } else if (organizationsHistory[_organizationAddress][_escrowIndex].isCompleted) {
            status = 2; // Completed
        } else if (organizationsHistory[_organizationAddress][_escrowIndex].isFinished) {
            status = 3; // Finished
        } else if (organizationsHistory[_organizationAddress][_escrowIndex].isReviewed) {
            status = 21; // In revision / dispute
        } else {
            status = 31; // Canceled
        }
        return (status);
    }

    function providerCompletitionNotice(address organizationAddress_, uint projectId_, uint transactionAmmount_) public {
        uint escrowId_ = uint(getTransactionNumber(organizationAddress_, msg.sender, projectId_, transactionAmmount_));
        require((organizationsHistory[organizationAddress_][escrowId_].isHired == true && organizationsHistory[organizationAddress_][escrowId_].isCompleted == false && organizationsHistory[organizationAddress_][escrowId_].isReviewed == false && organizationsHistory[organizationAddress_][escrowId_].isFinished == false), "The contract has already been terminated");
        
        // Set project to done from the provider part
        organizationsHistory[organizationAddress_][escrowId_].isCompleted = true;
        emit ProviderNotification(msg.sender, escrowId_);
    }

    // When transaction is complete, the organization will set approval for funds to be released.
    function organizationTransactionApproval(address providerAddress_, uint projectId_, uint transactionAmmount_) public {
        uint escrowId_ = uint(getTransactionNumber(msg.sender, providerAddress_, projectId_, transactionAmmount_));
        require((organizationsHistory[msg.sender][escrowId_].isCompleted == true && organizationsHistory[msg.sender][escrowId_].isReviewed == false && organizationsHistory[msg.sender][escrowId_].isFinished == false), "The contract has already been terminated");
        
        //Set release approval to true. Ensure approval for each transaction can only be called once.
        (bool successTransfer, ) = providerAddress_.call{value: organizationsHistory[msg.sender][escrowId_].netAmmount}("");
        require(successTransfer, "Transfer failed");
        organizationsHistory[msg.sender][escrowId_].isFinished = true;
        emit OrganizationApproval(msg.sender, escrowId_);
    }

    //Either buyer or seller can raise an issue with escrow agent. 
    //Once an issue is active, the escrow agent can release funds to the provider OR make a partial refund to the organization

    //Switcher = 0 for Organization, Switcher = 1 for Provider
    function EscrowEscalation(uint switcher, address _counterPartyAddress, uint projectId_, uint transactionAmmount_) public {
        uint escrowId_;
        if (switcher == 0) {
            escrowId_ = uint(getTransactionNumber(msg.sender, _counterPartyAddress, projectId_, transactionAmmount_));
            require(organizationsHistory[msg.sender][escrowId_].isFinished == false && organizationsHistory[msg.sender][escrowId_].isReviewed == false && organizationsHistory[msg.sender][escrowId_].isCanceled == false);
        } else {
            escrowId_ = uint(getTransactionNumber(_counterPartyAddress, msg.sender, projectId_, transactionAmmount_));
            require(organizationsHistory[_counterPartyAddress][escrowId_].isCompleted == false && organizationsHistory[_counterPartyAddress][escrowId_].isReviewed == false && organizationsHistory[_counterPartyAddress][escrowId_].isCanceled == false);
        }
        organizationsHistory[_counterPartyAddress][escrowId_].isReviewed = true;
    }
    
    // Decision = 0 is for refunding Organization [isCanceled turns true]. Decision = 1 is for releasing funds to provider [isFinished turns true without isCompleted]
    function escrowDecision(uint decision_, address providerAddress_, address organizationAddress_, uint projectId_, uint transactionAmmount_) public payable onlyOwner {
        uint escrowId_ = uint(getTransactionNumber(organizationAddress_, providerAddress_, projectId_, transactionAmmount_));
        require(organizationsHistory[organizationAddress_][escrowId_].isReviewed == true && organizationsHistory[organizationAddress_][escrowId_].isCanceled == false && organizationsHistory[organizationAddress_][escrowId_].isFinished == false);
        if (decision_ == 0) {
            (bool successRefund, ) = organizationAddress_.call{value: (organizationsHistory[organizationAddress_][escrowId_].netAmmount + organizationsHistory[organizationAddress_][escrowId_].providerFee)}("");
            require(successRefund, "The refunding has fail");
            organizationsHistory[organizationAddress_][escrowId_].isCanceled = true;
        } else {
            (bool successTransfer, ) = providerAddress_.call{value: (organizationsHistory[organizationAddress_][escrowId_].netAmmount)}("");
            require(successTransfer, "The transfer has fail");
            organizationsHistory[organizationAddress_][escrowId_].isFinished = true;
        }
        emit DecisionNotification(organizationAddress_, providerAddress_, escrowId_);
    }
}