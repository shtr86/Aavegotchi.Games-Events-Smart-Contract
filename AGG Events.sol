// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.7;

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

contract AGGSmartEvents {
    address payable DevWallet;
    bool locked;
    
    mapping(address => bool) approvedAddresses;
    mapping(address => mapping(address => uint)) Balances;

    event WithdrawBalance(address indexed by, address indexed tokenaddress, uint256 value);
    event EventNewSignUP(uint indexed eventid, uint indexed gotchiid, address indexed playeraddress);
    event EventNewSignOut(uint indexed eventid, uint indexed gotchiid, address indexed playeraddress);
    event EventRewarded(uint indexed eventid, uint indexed gotchiid, address indexed winneraddress, uint poisiton, uint amount, address tokenaddress);
    event EventStateChanged(uint indexed eventid, EventState oldstate, EventState newstate);
    event EventNewConfirmation(uint indexed eventid, address indexed by, bool IsConfirmed);

    enum EventState{
        SignUp, // event is in sigup state
        Active, // event is in on-going state
        AwaitingConfirms, // positions are submitted. top players can vote to confirm the positions.
        AwaitingAdminValidation, // players voted... an admin must validate to start delivering the rewards.
        Withdrawable, // it passed all validations. top players can withdraw their rewards.
        Disproved, // Not confirmed by top players of this event (scores not confirmed in the time limit)
        Invalidated // event admin invalidated this event for some reasons.
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
        bool voted;
        bool withdrawn;
    }

    struct EventType {
        uint typeID;
        string eventTypeTitle;
        uint paymentTokenID;
        uint paymentTokenAmount;
        uint activeDurationHours;
        uint confirmDurationHours;
        uint entrySize;
        uint confirmationSize;
        uint confirmationHighestAllowedPosition;
        mapping (uint => RewardDistributionRule) RewardDistributionRules;
        uint RewardDistributionRulesCount;
    }

    struct AGGEvent { // AaveGotchi.Games Events structure
        mapping (uint => Player) playersByGotchiID; // GotchiID => Player
        mapping (uint => uint) GotchiIDByIndex; // Index => GotchiID
        uint playersSize;
        uint eventTypeID;
        EventState state;
        address validator;
        bool isBusy;
    }

    struct RewardDistributionRule {
        uint fromPos;
        uint toPos;
        uint AmountEachPos;
    }

    uint internal lastEventID;

    Token[] internal tokens;
    EventType[] internal eventTypes;
    AGGEvent[] internal events;

    mapping (address => bool) validators;
    mapping (address => bool) bannedAddresses;
    mapping (uint => bool) bannedGotchis;

    modifier onlyDev() {
        require(msg.sender == DevWallet, "Not a Dev!");
        _;
    }

    modifier onlyValidator(uint event_id, address senderAddress) {
        require(senderAddress != address(0) && validators[senderAddress] && events[event_id].validator == senderAddress, "Not a validator!");
        _;
    }

    modifier onlyContestants(uint event_id, uint gotchiid, address senderAddress) {
        require(senderAddress != address(0) && events[event_id].playersByGotchiID[gotchiid].playerAddress == senderAddress, "Not a contestant!");
        _;
    }

    modifier validAddress(address _addr) {
        require(_addr != address(0), "Not a valid address!");
        _;
    }



    modifier lockUP() {
        require(!locked, "No ReEnterancy!");

        locked = true;
        _;
        locked = false;
    }

    modifier lockUpEvent(uint eventTypeID) {
        if (lastEventID < events.length && events[lastEventID].playersSize >= (eventTypes[eventTypeID].entrySize - 1)) {
            require(!events[lastEventID].isBusy || events[lastEventID].state != EventState.SignUp, "Someone else is taking the last spot on that specific event! to prevent conflicts, We need you to try again...");
            events[lastEventID].isBusy = true;
            _;
            events[lastEventID].isBusy = false;
        } else {
            _;
        }
    }

    function changeDev(address _newDevWallet) public onlyDev validAddress(_newDevWallet) {
        DevWallet = payable(_newDevWallet);
    }

    constructor() {
        DevWallet = payable(msg.sender);
    }

    function defineNewToken(address tokenAddress, bool withdrawable, bool depositable) onlyDev public {
        uint newIndex = tokens.length;
        tokens.push(Token(newIndex, tokenAddress, withdrawable, depositable));
    }

    function editToken(uint tokenID, address newAddress, bool withdrawable, bool depositable) onlyDev public {
        require(tokenID >= 0 && tokenID < tokens.length, "No such token to edit!");
        tokens[tokenID] = Token(tokenID, newAddress, withdrawable, depositable);
    }


    function defineNewEventType(string memory title, uint tokenID, uint tokenAmount, uint durationHours, uint confirmationHours, uint entrySize, uint confimationSize, uint confrimationHighestPosition, uint[3][] memory RewardDistributionRules) onlyDev lockUP public {
        uint newIndex = eventTypes.length;
        eventTypes.push();

        require(RewardDistributionRules.length > 0, "Please define the Reward distribution rules!");
        require(tokenID >= 0 && tokenID < tokens.length, "No such coinID!");

        EventType storage tmpEventType = eventTypes[newIndex];

        tmpEventType.typeID = newIndex;
        tmpEventType.eventTypeTitle = title;
        tmpEventType.paymentTokenID = tokenID;
        tmpEventType.paymentTokenAmount = tokenAmount;
        tmpEventType.activeDurationHours = durationHours;
        tmpEventType.confirmDurationHours = confirmationHours;
        tmpEventType.entrySize = entrySize;
        tmpEventType.confirmationSize = confimationSize;
        tmpEventType.confirmationHighestAllowedPosition = confrimationHighestPosition;

        for (uint i = 0; i < RewardDistributionRules.length; i++) {
            require(RewardDistributionRules[i].length > 2, "Please define the Reward distribution rules correctly!");
            tmpEventType.RewardDistributionRules[i] = RewardDistributionRule(RewardDistributionRules[i][0], RewardDistributionRules[i][1], RewardDistributionRules[i][2]);
            tmpEventType.RewardDistributionRulesCount++;
        }

    }

    function setEventPositionDataAndEnd(uint eventID, uint[2][] memory eventPositions) onlyDev lockUP public {
        require(eventID >= 0 && eventID < events.length, "No such event!");
        require(events[eventID].state == EventState.Active, "Event Already Ended!");

        events[eventID].state = EventState.AwaitingConfirms;

        for (uint i = 0; i < eventPositions.length; i++) {
            require(eventPositions[i].length > 1, "Please define the Reward distribution rules correctly!");
            require(events[eventID].playersByGotchiID[eventPositions[i][0]].playerAddress != address(0), "TokenID Not Exists in this event");
            events[eventID].playersByGotchiID[eventPositions[i][0]].position = eventPositions[i][1];
        }
    }

 
    function getEventPositionsData(uint eventID) public view returns(string[] memory) {
        require(eventID >= 0 && eventID < events.length, "No such event!");
        string[] memory output = new string[](events[eventID].playersSize);

        for (uint i = 0; i < events[eventID].playersSize; i++) {
            uint gotchiID = events[eventID].GotchiIDByIndex[i];
            output[i] = string(abi.encodePacked("[", events[eventID].playersByGotchiID[gotchiID].gotchiid, ",", events[eventID].playersByGotchiID[gotchiID].position, ",", events[eventID].playersByGotchiID[gotchiID].playerAddress, ",", events[eventID].playersByGotchiID[gotchiID].voted, "]"));
        }

        return output;
    }

    function getEventTypesCount() public view returns(uint) {
        return eventTypes.length;
    }

    function isApproved() public view returns(bool){
        return approvedAddresses[msg.sender];
    }

    function signUp(uint eventTypeID, uint gotchiid) lockUpEvent(eventTypeID) external {
        require(eventTypeID >= 0 && eventTypeID < eventTypes.length, "No such eventType!");
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
        tmpPlayer.withdrawn = false;

        if (lastEventID >= events.length) {
            lastEventID = events.length;
            events.push();
            events[lastEventID].eventTypeID = eventTypeID;
        }

        require(events[lastEventID].state == EventState.SignUp, "This event is not open for new signups! try again for a new one...");
        require(events[lastEventID].playersByGotchiID[gotchiid].playerAddress == address(0), "This Gotchi is already registered in this event!");

        events[lastEventID].playersByGotchiID[gotchiid] = tmpPlayer;
        events[lastEventID].GotchiIDByIndex[events[lastEventID].playersSize] = gotchiid;
        events[lastEventID].playersSize++;
  
        emit EventNewSignUP(lastEventID, gotchiid, msg.sender);

        if (eventTypes[eventTypeID].entrySize == events[lastEventID].playersSize) {
            events[lastEventID].state = EventState.Active;
            lastEventID++; // new event will be created for the next signup if this(lastEventID's) event is not created yet...
        }
    }
}