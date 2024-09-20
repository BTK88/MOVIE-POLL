import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
// Importerar OpenZeppelins ReentrancyGuard kontrakt, vilket är en säkerhetsfunktion för att förhindra återinträdesattacker. 
// ReentrancyGuard skyddar genom att tillåta att en specifik funktion endast kan kallas en gång åt gången, vilket minimerar risken för återinträdesattacker.

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract MovieVoting is ReentrancyGuard {
    // Arver från ReentrancyGuard för att använda `nonReentrant`-modifiern och skydda funktioner från återinträdesattacker.

    enum VotingState { NotStarted, Ongoing, Finished }
    // Enum används för att representera de olika tillstånden som en röstning kan ha:
    // - NotStarted: Röstningen har skapats men har inte börjat än.
    // - Ongoing: Röstningen pågår och användare kan rösta.
    // - Finished: Röstningen har avslutats och ingen mer röstning kan ske.

    struct Movie {
        string name; // Namnet på filmen.
        uint voteCount; // Antalet röster filmen har fått.
    }
    // Struct som representerar en film med dess namn och antalet röster den har fått.

    constructor() {
        votingCount = 0;
    }
    // Konstruktor som initierar `votingCount` till 0 när kontraktet distribueras.

    struct Voting {
        address creator; // Adressen till den som skapade röstningen.
        uint endTime; // Tiden då röstningen avslutas (Unix-tid).
        VotingState state; // Nuvarande tillstånd för röstningen.
        Movie[] movies; // Lista över filmer som är med i röstningen.
        mapping(address => bool) hasVoted; // Håller reda på vilka användare som har röstat.
    }
    // Struct som representerar en röstning med all nödvändig information.

    mapping(uint => Voting) public votings;
    // Mapping för att lagra alla röstningar baserat på ett unikt ID (uint).
    
    uint public votingCount;
    // Håller reda på antalet skapade röstningar.

    event VotingCreated(uint indexed votingId, address indexed creator, uint endTime);
    // Event som triggas när en ny röstning skapas.

    event VoteCast(uint indexed votingId, address indexed voter, string movie);
    // Event som triggas när en röst har lagts på en specifik film i en specifik röstning.

    event VotingFinished(uint indexed votingId, string winner);
    // Event som triggas när en röstning avslutas och vinnaren har bestämts.

    error VotingNotStarted(uint votingId);
    // Custom error för när en användare försöker interagera med en röstning som inte har startat än.

    error VotingAlreadyFinished(uint votingId);
    // Custom error för när en användare försöker interagera med en röstning som redan är avslutad.

    error NotEligibleToVote(uint votingId);
    // Custom error för när en användare försöker rösta men redan har röstat.

    error MovieNotFound(uint votingId, string movie);
    // Custom error för när en användare försöker rösta på en film som inte finns i den aktuella röstningen.

    error VotingExpired(uint votingId);
    // Custom error för när en användare försöker rösta efter att röstningens sluttid har passerat.

    error MovieNameEmpty();
    // Custom error för när en användare försöker skapa en röstning utan att tillhandahålla några filmtitlar.

    modifier onlyCreator(uint _votingId) {
        require(msg.sender == votings[_votingId].creator, "Not the creator");
        // Modifier som säkerställer att endast skaparen av en röstning kan kalla vissa funktioner.
        _;
    }

    modifier inState(uint _votingId, VotingState _state) {
        require(votings[_votingId].state == _state, "Invalid state");
        // Modifier som säkerställer att röstningen är i ett specifikt tillstånd (t.ex. att den har startat).
        _;
    }

    receive() external payable {
        revert("Direct ETH transfers are not allowed");
    }
    // Receive-funktion som avvisar alla direkta ETH-överföringar till kontraktet.

    fallback() external {
        revert("Fallback function not supported");
    }
    // Fallback-funktion som avvisar alla oprognostiserade anrop till kontraktet.

    function createVoting(string[] memory _movies, uint _duration) public {
        require(_movies.length > 0, "No movies provided");
        // Kontrollerar att det finns åtminstone en film att rösta på.

        Voting storage newVoting = votings[votingCount++];
        // Skapar en ny röstning och ökar `votingCount` med 1.

        newVoting.creator = msg.sender;
        newVoting.endTime = block.timestamp + _duration;
        newVoting.state = VotingState.NotStarted;
        // Sätter initiala värden för röstningen, inklusive slutdatum baserat på _duration.

        for (uint i = 0; i < _movies.length; i++) {
            newVoting.movies.push(Movie({ name: _movies[i], voteCount: 0 }));
        }
        // Lägger till varje film i röstningens filmslista.

        emit VotingCreated(votingCount - 1, msg.sender, newVoting.endTime);
        // Triggar eventet `VotingCreated`.
    }

    function startVoting(uint _votingId) public onlyCreator(_votingId) inState(_votingId, VotingState.NotStarted) {
        votings[_votingId].state = VotingState.Ongoing;
        // Startar röstningen genom att ändra status till Ongoing.
    }

    function getVoting(uint _votingId) public view returns (address, uint, VotingState, Movie[] memory) {
        Voting storage voting = votings[_votingId];
        return (voting.creator, voting.endTime, voting.state, voting.movies);
        // Returnerar information om en specifik röstning.
    }

    function hasUserVoted(uint _votingId, address _user) public view returns (bool) {
        return votings[_votingId].hasVoted[_user];
        // Kontrollerar om en specifik användare redan har röstat i en viss röstning.
    }

    function vote(uint _votingId, string memory _movieName) public nonReentrant inState(_votingId, VotingState.Ongoing) {
        require(bytes(_movieName).length > 0, "Movie name cannot be empty");
        // Säkerställer att filmtiteln inte är tom.

        Voting storage voting = votings[_votingId];

        if (voting.hasVoted[msg.sender]) {
            revert NotEligibleToVote(_votingId);
        }
        // Kontrollerar om användaren redan har röstat.

        if (block.timestamp >= voting.endTime) {
            revert VotingExpired(_votingId);
        }
        // Kontrollerar om röstningen har gått ut.

        bool found = false;
        Movie[] storage movies = voting.movies;

        for (uint i = 0; i < movies.length; i++) {
            if (keccak256(bytes(movies[i].name)) == keccak256(bytes(_movieName))) {
                movies[i].voteCount += 1;
                found = true;
                break;
            }
        }
        // Loopar igenom alla filmer och ökar röstantalet för den valda filmen om den hittas.

        if (!found) {
            revert MovieNotFound(_votingId, _movieName);
        }
        // Om filmen inte hittas, revertar funktionen med `MovieNotFound`.

        voting.hasVoted[msg.sender] = true;
        // Markerar att användaren har röstat.

        emit VoteCast(_votingId, msg.sender, _movieName);
        // Triggar eventet `VoteCast`.
    }

    function finishVoting(uint _votingId) public nonReentrant onlyCreator(_votingId) inState(_votingId, VotingState.Ongoing) {
        require(block.timestamp >= votings[_votingId].endTime, "Voting still ongoing");
        // Säkerställer att röstningen har avslutats innan den kan avslutas officiellt.

        Voting storage voting = votings[_votingId];
        voting.state = VotingState.Finished;
        // Ändrar status till Finished.

        string memory winner;
        uint maxVotes = 0;
        uint tieCount = 0;

        for (uint i = 0; i < voting.movies.length; i++) {
            if (voting.movies[i].voteCount > maxVotes) {
                maxVotes = voting.movies[i].voteCount;
                winner = voting.movies[i].name;
                tieCount = 1; 
            } else if (voting.movies[i].voteCount == maxVotes) {
                tieCount++;
            }
        }
        // Räknar fram den vinnande filmen baserat på högst antal röster. Hanterar oavgjort.

        if (tieCount > 1) {
            uint randomIndex = uint(keccak256(abi.encodePacked(block.timestamp, block.prevrandao))) % voting.movies.length;
            winner = voting.movies[randomIndex].name;
        }
        // Hanterar oavgjort genom att slumpmässigt välja en vinnare.

        emit VotingFinished(_votingId, winner);
        // Triggar eventet `VotingFinished` med den vinnande filmen.
    }
}