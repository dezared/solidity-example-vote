// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18; 

/*

    Задача:

    - Контракт должен создавать объект голосования, принимая на вход массив адресов кандидатов.
    - Голосований может быть много, по всем нужно иметь возможность посмотреть информацию.
    - Голосование длится некоторое время.
    - Пользователи могут голосовать за кандидата, переводя на контракт эфир.
    - По завершении голосования победитель может снять средства, которые были внесены в это голосование, за исключением комиссии площадки.
    - Владелец площадки должен иметь возможность выводить комиссию.

*/

/** @title Основной контракт голосования **/
contract VotingContract {
    // Администратор контракта ( владелец )
    address public ownerContract;

    // Максимальное количество кандидатов
    uint256 public maxCandidatesNum;

    // Переменаня, хранящая номер голосования
    uint256 public counterVotings;

    /** @title Структура кандидата **/
    struct Candidate {
        // Существует ли канидидат?
        bool valid;
        // Баланс кандидата
        uint256 votingBalance;
    }

    /** @title Структура голосования **/
    struct Voting {
        // Активно ли сейчас данное голосование
        bool isActive;

        // Победитель текущего голосования
        address winner;

        // Время начала голосования
        uint256 startTimeStamp;

        // Длительность голосования
        uint256 period;

        // Баланс победителя на начало конец
        uint256 winnerBalanceAtVotingClose;

        // Баланс контракта на момент голосования
        uint256 bankBalance;

        // Список кандидатов на победу
        mapping(address => Candidate) candidates;
    }

    // Список голосований
    mapping(uint256 => Voting) private votings;

    // Комиссия сервиса. Устанавливается один раз в конструкторе смарт-контракта ( в процентах )
    uint8 public immutable commision;

    constructor(uint8 _commision) {
        commision = _commision;
        ownerContract = msg.sender;
        maxCandidatesNum = 5;
    }

    // Проголосовать за кандидата
    function iAmVote(uint256 _votingId, address _to) public payable {
        require(votings[_votingId].isActive == true, "Voting is not started or not exist.");
        require(votings[_votingId].startTimeStamp + votings[_votingId].period > block.timestamp, "Voting is ended.");
        require(checkCandidate(_votingId, _to), "Candidate does not exist on this voting");

        votings[_votingId].candidates[_to].votingBalance += msg.value;

        if(votings[_votingId].candidates[_to].votingBalance > votings[_votingId].winnerBalanceAtVotingClose)
        {
            votings[_votingId].winner = _to;
            votings[_votingId].winnerBalanceAtVotingClose = votings[_votingId].candidates[_to].votingBalance;
        }
    }

    // Начать процедуру голсования
    function StartVoting(uint256 _votingId) public onlyOwner
    {
        votings[_votingId].isActive = true;
        votings[_votingId].startTimeStamp = block.timestamp;

        emit votingStarted(_votingId, block.timestamp);
    }

    // Проверить, существует ли кандидат в определённых голосованиях
    function checkCandidate(uint256 _votingId, address _candidate)
        public
        view
        returns (bool)
    {
        return (votings[_votingId].candidates[_candidate].valid);
    }

    // Получить информацию по голосованию
    function getVotingInfo(uint256 _votingId) public view returns (
        bool isActive,
        address winner,
        uint256 startTimeStamp,
        uint256 winnerBalanceAtVotingClose,
        uint256 bankBalance
    )
    {
        return (
            votings[_votingId].isActive,
            votings[_votingId].winner,
            votings[_votingId].startTimeStamp,
            votings[_votingId].winnerBalanceAtVotingClose,
            votings[_votingId].bankBalance
        );
    }

    // Добавить кандидата на голосование
    function addCandidate(uint256 _votingId, address _candidate) public onlyOwner {
        require(votings[_votingId].isActive == false, "Voting has already begun!");
        votings[_votingId].candidates[_candidate].valid = true;

        emit candidateInfo(_votingId, _candidate, true);
    }

    // Создать голосование
    function addVoting(uint256 _period, address[] calldata _candidates) public onlyOwner
    {
        require(_candidates.length < maxCandidatesNum, "Too many candidates!");

        votings[counterVotings].period = _period;
        for (uint256 i = 0; i < _candidates.length; i++) {
            addCandidate(counterVotings, _candidates[i]);
        }

        emit votingCreated(counterVotings);
        counterVotings++;
    }

    // Начать голосовние
    function startVoting(uint256 _votingId) public onlyOwner {
        votings[_votingId].isActive = true;
        votings[_votingId].startTimeStamp = block.timestamp;
        emit votingStarted(_votingId, block.timestamp);
    }

    // Изменить период голосования
    function editVotingPeriod(uint256 _votingId, uint256 _newPeriod) public onlyOwner
    {
        require(votings[_votingId].isActive == false, "Voting has already begun!");
        votings[_votingId].period = _newPeriod;
    }

    // Удалить кандидата из голосования
    function deleteCandidate(uint256 _votingId, address _candidate) public onlyOwner
    {
        require(votings[_votingId].isActive == false, "Voting has already begun!");
        votings[_votingId].candidates[_candidate].valid = false;
        emit candidateInfo(_votingId, _candidate, false);
    }

    // Установить максимальное число кандидатов
    function setMaxCandidatesNum(uint256 _maxCandidatesNum) public onlyOwner {
        maxCandidatesNum = _maxCandidatesNum;
    }

    // Получить приз
    function WithdrowMyPrize(uint256 _votingId) public {
        require(votings[_votingId].isActive == true, "Voting not started yet");
        require(votings[_votingId].startTimeStamp + votings[_votingId].period < block.timestamp, "Voting is not over yet!");
        require(msg.sender == votings[_votingId].winner, "You are not a winner!");
        require(votings[_votingId].bankBalance > 0, "You have already received your prize!");

        uint256 amount = votings[_votingId].bankBalance;
        uint256 ownersComission = (commision * amount) / 100;
        uint256 clearAmount = amount - ownersComission;

        votings[_votingId].bankBalance = 0;

        // отправить комиссию создателю
        payable(ownerContract).transfer(ownersComission);

        // отправить приз победителю
        payable(msg.sender).transfer(clearAmount);
    }

    // Только для владельца контракта
    modifier onlyOwner() {
        require(
            msg.sender == ownerContract,
            "Error! You're not the smart contract owner!"
        );
        _;
    }

    event votingStarted(uint256 indexed votingId, uint256 startTimeStamp);
    event candidateInfo(uint256 indexed votingId, address indexed candidate, bool valid);
    event votingCreated(uint256 indexed votingId);
}