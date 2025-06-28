function matchesResponse(match) {
  return (res) => res.split('|')[0] === match
}
function connect(endpoint) {
  const ws = new WebSocket(endpoint)
  const callbacks = []
  const messages = [];
  const backlog = [];
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

function drawVote(user, vote, myVote, hidden = true) {
  const div = document.createElement('div');
  div.innerText = vote;
  div.classList.add("vote");
  div.dataset.user = user;
  myVote && div.classList.add("my_vote");
  hidden && div.classList.add("hidden_vote");
  return div;
}

function revealVotes() {
  [...document.querySelectorAll('.vote')].forEach(vote => vote.classList.remove('hidden_vote'));
}

function drawVotes(votes, currentUser) {
  const voteDivs = votes.map(({userId, vote}) => drawVote(userId, vote, userId === currentUser, userId !== currentUser))
  document.querySelector("#voting_area").replaceChildren(voteDivs); 
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
  const ws = connect('ws://localhost:9000/ws');
  const roomNameDiv = document.querySelector("#room_name");
  const createRoomButton = document.querySelector("#room_button");
  const shareButton = document.querySelector("#share_button");
  const votingArea = document.querySelector('#voting_area');
  const userId = getOrSetUserId();

  votingArea.addEventListener("click", (e) => {
    console.log("poop")
    const url = new URL(window.location)
    const roomName = url.searchParams.get("roomName");
    if (!roomName) {
      console.warn("Not in a room ignorning vote");
      return;
    }
    vote = e.target.dataset?.quantity;
    ws.send(JSON.stringify({command: "vote", value: `${roomName}:${vote}`}));
    console.log(vote);
  })

  shareButton.addEventListener("click", () => {
    const currentUrl = window.location.href;
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

  createRoomButton.addEventListener("click", () => {
    ws.send("createRoom");
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
      const votes = JSON.parse(message.replace("joinRoom|", ""));
      if (votes.error) {
        console.warn("room not found");
        setRoom(null);
      } else {
        console.log('votes in room', votes);
        drawVotes(votes);
      }
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
      drawVotes(votes);
    },
    filter: matchesResponse("votes")
  })

  setInterval(() => {
    ws.send(JSON.stringify({
      command: "userPing",
      value: userId,
    }));
  }, 30000);

  window.onbeforeunload = () => {
    ws.send(JSON.stringify({
      command: "leaveRoom",
      value: `${roomName}:${userId}`,
    }));
  }
})

