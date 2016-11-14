#!/bin/sh

. /usr/share/libubox/jshn.sh

log_network() {
	logger -s -t ffwizard_network "$@"
}

v4_get_subnet_first_ip() {
  eval "$(ipcalc.sh $1)"
  local OCTET_4="${NETWORK##*.}"
	local OCTET_1_3="${NETWORK%.*}"
	OCTET_4="$((OCTET_4 + 1))"
	echo "$OCTET_1_3.$OCTET_4/$PREFIX"
}

setup_network() {
	local cfg=$1
	json_init
	json_load "$CONFIG_JSON" || exit 1
	json_select config

	json_select ip

  local meshLan
  json_get_var meshLan meshLan

  # get lan ifname and mac
  local lanIfname="$(uci get network.lan.ifname)"
  if [ -z "$lanIfname" ]; then
    log_network "could not determine lan ifname."
    exit 1
  fi
  # required for dhcp interface on wdr4300
  local lanMacaddr="$(uci -q get network.lan.macaddr)"

  # v6 prefix
  local v6Prefix
  uci -q delete network.loopback.ip6prefix
  json_get_var v6Prefix v6Prefix
  if [ -n "$v6Prefix" ]; then
    uci set "network.loopback.ip6prefix=$v6Prefix"
  fi

  # lan interface (used for mesh or disabled if meshLan is true)
  uci -q delete network.lan
  uci -q delete network.lanbat

  uci set "network.lan=interface"
  uci set "network.lan.ifname=$lanIfname"
  uci set "network.lan.macaddr=$lanMacaddr"
  if [ "$meshLan" == "1" ]; then
    uci set "network.lan.proto=static"
    uci set "network.lan.ip6assign=64"
    uci set "network.lan.mtu=1532"

    json_select v4
    local v4Lan
    json_get_var v4Lan lan
    if [ -z "$v4Lan" ]; then
      log_network "meshLan is true but v4.lan is missing"
      exit 1
    fi
    eval "$(ipcalc.sh $v4Lan)"
    uci set "network.lan.ipaddr=$IP/32"
    json_select ..

    uci set "network.lanbat=interface"
    uci set "network.lanbat.proto=batadv"
    #uci set "network.lanbat.ifname=@lan"
    uci set "network.lanbat.mesh=bat0"
    uci set "network.lanbat.mtu=1532"
  else
    uci set "network.lan.proto=none"
    uci set "network.lan.enabled=0"
  fi

  # dhcp interface (bridge with lanIfname if meshLan is false)
  uci -q delete network.dhcp
  uci set "network.dhcp=interface"
  uci set "network.dhcp.type=bridge"

  local dhcpIfnames="bat0"
  if [ "$meshLan" != "1" ]; then
    dhcpIfnames="$dhcpIfnames $lanIfname"
    uci set "network.dhcp.macaddr=$lanMacaddr"
  fi
  uci set "network.dhcp.ifname=$dhcpIfnames"

  # see https://github.com/freifunk-berlin/firmware/issues/297
  uci set "network.dhcp.igmp_snooping=0"

  local distribute;
  json_get_var distribute distribute
  if [ "$distribute" == "1" ]; then
    local v4ClientSubnet
    if ! json_get_var v4ClientSubnet v4ClientSubnet; then
      log_network "v4ClientSubnet missing."
      exit 1
    fi
    local v4ClientSubnetFirst=$(v4_get_subnet_first_ip $v4ClientSubnet)
    uci set "network.dhcp.proto=static"
    uci set "network.dhcp.ip6assign=64"
    uci set "network.dhcp.ipaddr=$v4ClientSubnetFirst"
  else
    uci set "network.dhcp.proto=dhcp"
  fi

  uci commit network
}

setup_network
