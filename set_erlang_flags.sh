echo "${ERLANG_BASENAME}"

# if we're in a fly environment use that ip otherwise use the host's ip
if [ -n "${FLY_PRIVATE_IP}" ]; then
  HOSTIP="${FLY_PRIVATE_IP}"
else
  HOSTIP=$(hostname -i)
fi

echo "SETTING ERL_AFLAGS"
export ERL_AFLAGS="-name ${ERLANG_BASENAME}@${HOSTIP} ${EXTRA_ERL_AFLAGS}"
echo "${ERL_AFLAGS}"
# avoid logging cookie
export ERL_AFLAGS="${ERL_AFLAGS} -setcookie ${ERLANG_COOKIE}"

/app/entrypoint.sh run
