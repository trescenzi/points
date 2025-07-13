echo "${ERLANG_BASENAME}"
echo "${ERLANG_COOKIE}"
HOSTIP=$(hostname -i)

echo "SETTING ERL_AFLAGS"
export ERL_AFLAGS="-name ${ERLANG_BASENAME}@${HOSTIP} -setcookie ${ERLANG_COOKIE} ${EXTRA_ERL_AFLAGS}"
echo "${ERL_AFLAGS}"

/app/entrypoint.sh run
