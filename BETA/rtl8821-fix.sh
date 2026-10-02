#!/bin/bash

sudo ln -sf rtl_bt/rtl8821c_fw.bin /lib/firmware/rtl8821c_fw
sudo ln -sf rtl_bt/rtl8821c_config.bin /lib/firmware/rtl8821c_config

ls -l /lib/firmware/rtl8821c_*

sleep 2