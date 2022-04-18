// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.7;

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

contract AGGSmartEvents {
    address payable DevWallet;
    bool locked;
    
    mapping(address => mapping(address => uint)) Balances; // senderAddress + TokenAddres => balance
    mapping (address => bool) validators;
    mapping (address => bool) System;
    mapping(address => bool) approvedAddresses;
    mapping (address => bool) bannedAddresses;
    mapping (uint => bool) bannedGotchis;

    event WithdrawBalance(address indexed by, address indexed tokenaddress, uint256 value);
    event EventNewSignUP(uint indexed eventid, uint indexed gotchiid, address indexed playeraddress);
    event EventNewSignOut(uint indexed eventid, uint indexed gotchiid, address indexed playeraddress);
    event EventRewarded(uint indexed eventid, uint indexed gotchiid, address indexed winneraddress, uint poisiton, uint amount, address tokenaddress);
    event EventStateChanged(uint indexed eventid, EventState oldstate, EventState newstate);
    event EventNewConfirmation(uint indexed eventid, address indexed by, bool IsConfirmed);
    event EventValidated(uint indexed eventid, address indexed by, bool IsConfirmed);

    enum EventState{
        SignUp, // event is in signup state
        Active, // event is in on-going state
        AwaitingConfirms, // positions are submitted. top players can vote to confirm the positions.
        AwaitingAdminValidation, // players voted... an admin must validate to start delivering the rewards.
        Withdrawable, // it passed all validations. top players can withdraw their rewards.
        Reverted // Not Validated. all balances reverted.
    }

    struct Token{
        uint tokenID;
        address tokenAddress;
        bool withdrawable;
        bool depositable;
    }

    struct Player {
        uint gotchiid;
        uint position;
        address payable playerAddress;
        bool vote;
        bool voted;
        string optionalReason;
    }

    struct EventType {
        uint typeID;
        string eventTypeTitle;
        uint paymentTokenID;
        uint paymentTokenAmount;
        uint activeDurationHours;
        uint confirmDurationHours;
        uint entrySize;
        bool needConfrimation;
        uint confirmationSize;
        uint confirmationHighestAllowedPosition;
        mapping (uint => DistributionRule) DistributionRules;
        uint DistributionRulesCount;
    }

    struct AGGEvent { // AaveGotchi.Games Events structure
        mapping (uint => Player) playersByGotchiID; // GotchiID => Player
        mapping (uint => uint) GotchiIDByIndex; // Index => GotchiID
        uint playersSize;
        uint eventTypeID;
        EventState state;
        address validator;
        bool validatorVote;
        bool validatorVoted;
        string validatorOptionalReason;
        bool isBusy;
    }

    struct DistributionRule {
        uint fromPos;
        uint toPos;
        uint AmountEachPos;
    }

    uint internal lastEventID;

    Token[] internal tokens;
    EventType[] internal eventTypes;
    AGGEvent[] internal events;

    modifier onlyDev() {
        require(msg.sender == DevWallet, "Not a Dev!");
        _;
    }

    modifier onlyValidator(uint event_id) {
        require(msg.sender != address(0) && validators[msg.sender] && events[event_id].validator == msg.sender, "Not a validator!");
        _;
    }

    modifier onlySystem() {
        require(msg.sender != address(0) && System[msg.sender], "Not a System Address!");
        _;
    }

    modifier validAddress(address _addr) {
        require(_addr != address(0), "Not a valid address!");
        _;
    }

    modifier validSender() {
        require(msg.sender != address(0), "Not a valid sender address");
        _;
    }

    modifier lockUP() {
        require(!locked, "No ReEnterancy!");

        locked = true;
        _;
        locked = false;
    }

    modifier lockUpEvent() {
        if (lastEventID < events.length) {
            require(!events[lastEventID].isBusy || events[lastEventID].state != EventState.SignUp, "No reEnterancy");
            events[lastEventID].isBusy = true;
            _;
            events[lastEventID].isBusy = false;
        } else {
            _;
        }
    }

    modifier checkEvent(uint eventID) {
        require(eventID >= 0 && eventID < events.length, "No such event!");
        _;
    } 

    modifier checkToken(uint tokenID) {
        require(tokenID >= 0 && tokenID < tokens.length, "No such tokenID!");
        _;
    } 

    function changeDev(address _newDevWallet) public onlyDev validAddress(_newDevWallet) {
        DevWallet = payable(_newDevWallet);
    }

    function setSystem(address _systemAddress, bool enabled) onlyDev validSender validAddress(_systemAddress) public {
        System[_systemAddress] = enabled;
    }

    constructor() {
        DevWallet = payable(msg.sender);
    }

    function defineNewToken(address tokenAddress, bool withdrawable, bool depositable) validSender onlyDev public {
        uint newIndex = tokens.length;
        tokens.push(Token(newIndex, tokenAddress, withdrawable, depositable));
    }

    function editToken(uint tokenID, address newAddress, bool withdrawable, bool depositable) checkToken(tokenID) validSender onlyDev public {
        tokens[tokenID] = Token(tokenID, newAddress, withdrawable, depositable);
    }


    function defineNewEventType(string memory title, uint tokenID, uint tokenAmount, uint durationHours, uint confirmationHours, uint entrySize, bool needConfrimation, uint confimationSize, uint confrimationHighestPosition, uint[3][] memory DistributionRules) checkToken(tokenID) onlyDev lockUP public {
        uint newIndex = eventTypes.length;
        eventTypes.push();

        require(DistributionRules.length > 0, "define distribution rules!");

        EventType storage tmpEventType = eventTypes[newIndex];

        tmpEventType.typeID = newIndex;
        tmpEventType.eventTypeTitle = title;
        tmpEventType.paymentTokenID = tokenID;
        tmpEventType.paymentTokenAmount = tokenAmount;
        tmpEventType.activeDurationHours = durationHours;
        tmpEventType.confirmDurationHours = confirmationHours;
        tmpEventType.entrySize = entrySize;
        tmpEventType.needConfrimation = needConfrimation;
        tmpEventType.confirmationSize = confimationSize;
        tmpEventType.confirmationHighestAllowedPosition = confrimationHighestPosition;

        for (uint i = 0; i < DistributionRules.length; i++) {
            require(DistributionRules[i].length > 2, "distribution rules InCorrect!");
            tmpEventType.DistributionRules[i] = DistributionRule(DistributionRules[i][0], DistributionRules[i][1], DistributionRules[i][2]);
            tmpEventType.DistributionRulesCount++;
        }
    }

    function setEventPositionDataAndEnd(uint eventID, uint[2][] memory eventPositions) checkEvent(eventID) onlyDev lockUP public {
        require(events[eventID].state == EventState.Active, "Event Already Ended!");

        emit EventStateChanged(eventID, events[eventID].state, EventState.AwaitingConfirms);
        events[eventID].state = EventState.AwaitingConfirms;

        for (uint i = 0; i < eventPositions.length; i++) {
            require(eventPositions[i].length > 1, "eventPositions InCorrect!");
            require(events[eventID].playersByGotchiID[eventPositions[i][0]].playerAddress != address(0), "TokenID Not Exists in this event");
            events[eventID].playersByGotchiID[eventPositions[i][0]].position = eventPositions[i][1];
        }
    }

     function signUp(uint eventTypeID, uint gotchiid) validSender lockUpEvent external {
        require(eventTypeID >= 0 && eventTypeID < eventTypes.length, "No such eventTypeID!");
        require(tokens[eventTypes[eventTypeID].paymentTokenID].depositable, "Token not depositable!");

        IERC20 paymentToken = IERC20(tokens[eventTypes[eventTypeID].paymentTokenID].tokenAddress);
        uint amountToPay = eventTypes[eventTypeID].paymentTokenAmount;
        
        if (paymentToken.allowance(msg.sender, address(this))  >= amountToPay) {
            approvedAddresses[msg.sender] = true;
        } else {
            approvedAddresses[msg.sender] = false;
        }

        require(paymentToken.allowance(msg.sender, address(this))  >= amountToPay, "Not approved for that amount!");
        require(paymentToken.transferFrom(msg.sender, address(this), amountToPay),"Transfer Failed!");
       
        Player memory tmpPlayer;

        tmpPlayer.gotchiid = gotchiid;
        tmpPlayer.position = 0;
        tmpPlayer.playerAddress = payable(msg.sender);
        tmpPlayer.voted = false;

        if (lastEventID >= events.length) {
            lastEventID = events.length;
            events.push();
            events[lastEventID].eventTypeID = eventTypeID;
        }

        require(events[lastEventID].state == EventState.SignUp, "not open for new signups!");
        require(events[lastEventID].playersByGotchiID[gotchiid].playerAddress == address(0), "Gotchi already registered!");

        events[lastEventID].playersByGotchiID[gotchiid] = tmpPlayer;

        bool filled;
        for (uint i=0; i<events[lastEventID].playersSize; i++) {
            if (events[lastEventID].GotchiIDByIndex[i] == 0) {
                events[lastEventID].GotchiIDByIndex[i] = gotchiid;
                events[lastEventID].playersSize++;
                filled=true;
            }
        }

        require(filled, "Couldn't find any empty slot...");

        if (eventTypes[eventTypeID].entrySize == events[lastEventID].playersSize) {
            emit EventStateChanged(lastEventID, events[lastEventID].state, EventState.Active);

            events[lastEventID].state = EventState.Active;
            lastEventID++; // new event will be created for the next signup if this(lastEventID's) event is not created yet...
        }

        emit EventNewSignUP(lastEventID, gotchiid, msg.sender);
    }

    function signOut(uint eventID, uint gotchiid) checkEvent(eventID) validSender lockUpEvent external {
        require(events[eventID].playersByGotchiID[gotchiid].playerAddress != address(0), "Gotchi isn't registered!");

        bool removed;
        for (uint i=0; i<events[lastEventID].playersSize; i++) {
            if (events[lastEventID].GotchiIDByIndex[i] == gotchiid) {
                events[lastEventID].GotchiIDByIndex[i] = 0;
                events[lastEventID].playersSize--;
                removed = true;
            }
        }

        require(removed, "Couldn't find the specific gotchiID!");

        Player memory emptyPlayer;
        events[lastEventID].playersByGotchiID[gotchiid]=emptyPlayer;

        emit EventNewSignOut(eventID, gotchiid, msg.sender);
    }

    function confirmEvent(uint eventID, bool vote, string memory optionalReason) checkEvent(eventID) validSender public {
        require(events[eventID].state == EventState.AwaitingConfirms, "Not in the confirmation state!");
        require(eventTypes[events[eventID].eventTypeID].needConfrimation, "Confirmation not necessary!");

        bool confirmed;
        for (uint i=0; i<events[eventID].playersSize; i++) {
            if (events[eventID].playersByGotchiID[events[eventID].GotchiIDByIndex[i]].playerAddress == msg.sender) {
                events[eventID].playersByGotchiID[events[eventID].GotchiIDByIndex[i]].vote = vote;
                events[eventID].playersByGotchiID[events[eventID].GotchiIDByIndex[i]].voted = true;
                events[eventID].playersByGotchiID[events[eventID].GotchiIDByIndex[i]].optionalReason = optionalReason;
                confirmed = true;
            }
        }

        require(confirmed, "not eligible to confirm");

        emit EventNewConfirmation(eventID, msg.sender, vote);
    }

    function validateEvent(uint eventID, bool vote, string memory optionalReason) checkEvent(eventID) validSender onlyValidator(eventID) public {
        require(events[eventID].state == EventState.AwaitingAdminValidation, "Not in the admin validation state!");

        events[eventID].validatorVote = vote;
        events[eventID].validatorOptionalReason = optionalReason;
        events[eventID].validatorVoted = true;

        emit EventValidated(eventID, msg.sender, vote);

        if (!eventTypes[events[eventID].eventTypeID].needConfrimation) {
            rewardPlayers(eventID);
            emit EventStateChanged(eventID, events[eventID].state, EventState.Withdrawable);
        } else {
            if (confirmationScore(eventID) > 0) {
                rewardPlayers(eventID);
                emit EventStateChanged(eventID, events[eventID].state, EventState.Withdrawable);
            } else {
                revertEvent(eventID);
                emit EventStateChanged(eventID, events[eventID].state, EventState.Reverted);
            }
        }
    }

    function confirmationScore(uint eventID) checkEvent(eventID) public view returns(uint) {

    }

    function rewardPlayers(uint eventID) internal {

    }

    function revertEvent(uint eventID) internal {

    }

    function balanceOfTokenID(uint tokenID) checkToken(tokenID) public view returns(uint) {
        return Balances[msg.sender][tokens[tokenID].tokenAddress];
    }

    function withdraw(uint tokenID, uint amount) checkToken(tokenID) validSender lockUP public {
        require(tokens[tokenID].withdrawable, "Token Not withdrawable!");
        require(amount <= Balances[msg.sender][tokens[tokenID].tokenAddress], "Not enough balance!");

        IERC20 token = IERC20(tokens[tokenID].tokenAddress);
        require(token.transfer(msg.sender, amount), "Transfer failed!");

        Balances[msg.sender][tokens[tokenID].tokenAddress] -= amount;

        emit WithdrawBalance(msg.sender, tokens[tokenID].tokenAddress, amount);
    }
}