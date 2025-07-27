function matchesResponse(match) {
  return (res) => res.split('|')[0] === match
}
function connect(endpoint) {
  const ws = new WebSocket(endpoint)
  const callbacks = []
  const messages = [];
  const backlog = [];
  let user_id = '';
  ws.onopen = () => {
    ws.send('ping')
    backlog.forEach(message => ws.send(message))
  }

  ws.onmessage = (message) => {
    const data = message.data
    messages.push(data);
    callbacks.forEach(({filter, callback}) => filter(data) && callback(data));
  }

  ws.onerror = (error) => {
    console.error(error);
  }

  ws.onclose = (message) => {
    console.log("CLOSED", message);
  }

  callbacks.push({
    filter: (message) => message.startsWith("connect"),
    callback: (message) => {
      const id = message.replace("connect|", "");
      console.log("connected as id:", id);
      user_id = id
    },
  })

  return {
    send: (msg) => {
      console.log("ws sending", msg, ws.readyState);
      if (ws.readyState === WebSocket.CLOSED ||
                 ws.readyState === WebSocket.CLOSING) {
        console.warn(`Message sent to closed websocket ${msg}`);
      } if (ws.readyState !== WebSocket.OPEN) {
        console.log("ws note open", msg);
        backlog.push(msg);
      } else {
        ws.send(msg)
      }
    },
    get_id: () => user_id,
    close: ()  => {
      callbacks = []
      messages = []
      ws.close()
    },
    addCallback: (callback, retro = false) => {
      callbacks.push(callback)
      if (retro) {
        messages.forEach(m => callback.filter(m) && callback.callback(m))
      }
    },
    removeCallback: (callback) => callbacks = callbacks.filter(c => c != callback)
  }
}

function drawVote({vote, user, user_type}, myVote, hidden = true) {
  console.log('drawing vote', vote, user, user_type);
  const hasntVoted = vote === -1 || vote == null;
  const div = document.createElement('div');
  const front = document.createElement('div');
  const back = document.createElement('div');
  const tl = document.createElement('div');
  tl.classList.add("tl");
  const tr = document.createElement('div');
  tr.classList.add("tr");
  const m = document.createElement('div');
  m.classList.add("m");
  const bl = document.createElement('div');
  bl.classList.add("bl");
  const br = document.createElement('div');
  br.classList.add("br");
  const value = hasntVoted ? "?" : vote;
  tl.innerText = value;
  tr.innerText = value;
  m.innerText = value;
  bl.innerText = value;
  br.innerText = value
  front.replaceChildren(tl, tr, m, bl, br)
  const backInner = document.createElement('div');
  backInner.classList.add("m");
  backInner.innerText = hasntVoted ? "?" : "✔️";
  back.replaceChildren(backInner);
  front.classList.add("front");
  back.classList.add("back");
  div.classList.add("vote");
  div.classList.add("vote_card");
  div.dataset.user = user;
  div.dataset.vote = vote;
  div.appendChild(front);
  div.appendChild(back);
  myVote && div.classList.add("my_vote");
  hidden && div.classList.add("hidden_vote");
  user_type === "spectator" && div.classList.add("hidden")
  return div;
}

function drawVotes(votes, currentUser, votesVisible) {
  console.log("drawing votes", votes);
  const voteDivs = Object.entries(votes)
    .map(([userId, vote]) => drawVote(vote, userId === currentUser, userId !== currentUser, votesVisible))
    // your vote is always first
    .sort((a, b) => a.classList.contains("my_vote") ? -1 : b.classList.contains("my_vote") ? 1 : 0)
  document.querySelector("#vote_area").replaceChildren(...voteDivs); 
}

function getOrSetUserId() {
  if(sessionStorage.getItem("point_user")) {
    return sessionStorage.getItem("point_user");
  } else {
    const userId = crypto.randomUUID();
    sessionStorage.setItem("point_user", userId);
    return userId;
  }
}

window.addEventListener('load', () => {
  const wsLocation = ((window.location.protocol === "https:") ? "wss://" : "ws://") + window.location.host + "/ws"
  const ws = connect(wsLocation);
  const roomNameDiv = document.querySelector("#room_name");
  const createRoomButton = document.querySelector("#room_button");
  const shareButton = document.querySelector("#share_button");
  const showButton = document.querySelector("#show_button");
  const resetButton = document.querySelector("#reset_button");
  const votingArea = document.querySelector('#voting_area');
  const userTypeCheckbox = document.querySelector('#user_type');
  const main = document.querySelector("main");
  let votesVisible = false;

  ws.addCallback({
    callback: (message) => {
      const votes = JSON.parse(message.replace("votes|", ""));
      console.log("GOT VOTES", votes);
      drawVotes(votes, ws.get_id(), votesVisible);
    },
    filter: matchesResponse("connect")
  })

  votingArea.querySelectorAll(".vote_option").forEach(card => card.addEventListener("click", (e) => {
    if (userTypeCheckbox.checked) return;
    const currentVote = document.querySelector("#voting_area .my_vote");
    currentVote?.classList.remove("my_vote");
    const url = new URL(window.location)
    const roomName = url.searchParams.get("roomName");
    if (!roomName) {
      console.warn("Not in a room ignorning vote");
      return;
    }
    vote = e.target.dataset?.quantity;
    if (vote) {
      console.log(e);
      card.classList.add("my_vote");
      ws.send(JSON.stringify({command: "vote", value: `${roomName}:${vote}`}));
      delete main.dataset.vote;
      setTimeout(() => main.dataset.vote = vote, 10)
      console.log(vote);
    }
  }));

  shareButton.addEventListener("click", () => {
    const currentUrl = window.location.href;main.js
    navigator.clipboard.writeText(currentUrl)
      .then(() => {
        const originalText = shareButton.innerText;
        shareButton.innerText = "Copied!";
        setTimeout(() => {
          shareButton.innerText = originalText;
        }, 2000);
      })
      .catch(err => {
        console.error('Failed to copy URL: ', err);
      });
  })

  showButton.addEventListener("click", () => {
    const url = new URL(window.location)
    const roomName = url.searchParams.get("roomName");
    ws.send(JSON.stringify({command: "showVotes", value: roomName}));
  })

  resetButton.addEventListener("click", () => {
    const url = new URL(window.location)
    const roomName = url.searchParams.get("roomName");
    ws.send(JSON.stringify({command: "resetVotes", value: roomName}));
  });

  createRoomButton.addEventListener("click", () => {
    ws.send("createRoom");
  });

  if (userTypeCheckbox.checked) {
    const url = new URL(window.location)
    const roomName = url.searchParams.get("roomName");
    ws.send(JSON.stringify({command: "setUserType", value: `${roomName}:spectator`}));
  }

  userTypeCheckbox.addEventListener("input", (e) => {
    /* checked === spectator */
    const type = e.target.checked ? 'spectator' : 'voter'
    const url = new URL(window.location)
    const roomName = url.searchParams.get("roomName");
    ws.send(JSON.stringify({command: "setUserType", value: `${roomName}:${type}`}));
  })

  function setRoom(roomName) {
    const url = new URL(window.location)

    if (!roomName) {
      url.searchParams.delete("roomName");
      history.pushState(null, '', url);
      roomNameDiv.innerText = "<>";
      shareButton.classList.add("hidden");
      createRoomButton.classList.remove("hidden");

      return;
    }

    url.searchParams.set("roomName", roomName);
    history.pushState(null, '', url);
    roomNameDiv.innerText = roomName;
    shareButton.classList.remove("hidden");
    createRoomButton.classList.add("hidden");
  }

  const initialRoom = new URL(window.location).searchParams.get('roomName')
  if (initialRoom) {
    ws.send(JSON.stringify({
      command: "joinRoom",
      value: `${initialRoom}`,
    }))
    setRoom(initialRoom);
  }

  ws.addCallback({
    callback: (message) => console.log(message),
    filter: () => true,
    retro: true,
  })

  ws.addCallback({
    callback: (message) => {
      console.log(message)
    },
    filter: matchesResponse("joinRoom")
  });

  ws.addCallback({
    callback: (message) => {
      const roomName = message.replace("createRoom|", "");
      setRoom(roomName);
      ws.send(JSON.stringify({
        command: "joinRoom",
        value: `${roomName}`,
      }))
    },
    filter: matchesResponse("createRoom")
  })

  ws.addCallback({
    callback: (message) => {
      const votes = JSON.parse(message.replace("votes|", ""));
      console.log("GOT VOTES", votes);
      drawVotes(votes, ws.get_id(), votesVisible);
    },
    filter: matchesResponse("votes")
  })

  ws.addCallback({
    callback: () => {
      votesVisible = true;
      [...document.querySelectorAll(".vote_card.hidden_vote")].forEach(card => {
        card.classList.remove("hidden_vote")
      })
      const voteCards = [...document.querySelectorAll("#vote_area .vote_card")];
      const votes = voteCards.map(card => card.dataset.vote ? parseInt(card.dataset.vote, 10) : 0)
      const sum = votes.reduce((sum, vote) => sum + vote, 0)
      const mean = (sum / votes.length).toPrecision(4);
      const std = Math.sqrt(votes.map(vote => Math.pow(vote - mean, 2)).reduce((a, b) => a + b) / votes.length).toPrecision(4);
      const mode = calculateMode(votes);
      document.querySelector("#mean").innerText = mean;
      document.querySelector("#mode").innerText = mode;
      document.querySelector("#std").innerText = std;
    },
    filter: matchesResponse("showVotes")
  })

  ws.addCallback({
    callback: () => {
      votesVisible = false;
      [...document.querySelectorAll("#vote_area .vote_card:not(.my_vote)")].forEach(card => {
        card.classList.add("hidden_vote")
      })
      document.querySelector("#mean").innerText = "--";
      document.querySelector("#std").innerText = "--";
    },
    filter: matchesResponse("resetVotes")
  })

  window.onbeforeunload = () => {
    ws.send(JSON.stringify({
      command: "leaveRoom",
      value: `${roomName}:${userId}`,
    }));
  }
})

function calculateMode(array) {
  const sortedArray = array.sort();
  const [_, __, mode] = sortedArray.reduce(([currentValue, currentCount, mode, modeCount], num) => {
    if (num === currentValue) {
      currentCount = currentCount + 1;
      if (currentCount > modeCount) {
        return [num, currentCount, num, currentCount];
      }
    } else {
      currentValue = num;
      currentCount = 1;
    }
    return [currentValue, currentCount, mode, modeCount];
  }, [sortedArray[0], 1, sortedArray[0], 1]);
  return mode;
}
