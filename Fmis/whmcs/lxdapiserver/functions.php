<?php

use WHMCS\Database\Capsule;

function lxdapiserver_generate_password($length = 16)
{
    $characters = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!@#$%^&*';
    $password = '';
    $charactersLength = strlen($characters);
    
    for ($i = 0; $i < $length; $i++) {
        $password .= $characters[rand(0, $charactersLength - 1)];
    }
    
    return $password;
}

function lxdapiserver_save_password($serviceid, $password)
{
    try {
        Capsule::table('tblhosting')
            ->where('id', $serviceid)
            ->update(['password' => encrypt($password)]);
        return true;
    } catch (Exception $e) {
        lxdapiserver_log_error('save_password', $e->getMessage());
        return false;
    }
}

function lxdapiserver_log_error($function, $message)
{
    logActivity('[lxdapi Server] ' . $function . ': ' . $message);
}
