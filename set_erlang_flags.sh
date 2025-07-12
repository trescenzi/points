echo "${ERLANG_BASENAME}"
echo "${ERLANG_COOKIE}"
HOSTIP=$(hostname -i)

echo "SETTING ERL_AFLAGS"
export ERL_AFLAGS="-name ${ERLANG_BASENAME}@${HOSTIP} -setcookie ${ERLANG_COOKIE}"
echo "${ERL_AFLAGS}"

/app/entrypoint.sh run
