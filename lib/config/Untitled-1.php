<?php
defined('BASEPATH') OR exit('No direct script access allowed');

$CI = &get_instance();

$active_group = 'default';
$query_builder = TRUE;


$subdomain = join('.', explode('.', $_SERVER['HTTP_HOST'], -4));

$maindomain = str_replace("www.","",$subdomain);

$db['default'] = array(
	'dsn'	=> '',
	'hostname' => 'localhost',
	'username' => 'root',
	'password' => 'xxxxxxxxx',
	'database' => 'rdkspdba_prov.'.$maindomain,
	'dbdriver' => 'mysqli',
	'dbprefix' => '',
	'pconnect' => FALSE,
	'db_debug' => (ENVIRONMENT !== 'production'),
	'cache_on' => FALSE,
	'cachedir' => '',
	'char_set' => 'utf8',
	'dbcollat' => 'utf8_general_ci',
	'swap_pre' => '',
	'encrypt' => FALSE,
	'compress' => FALSE,
	'stricton' => FALSE,
	'failover' => array(),
	'save_queries' => TRUE
);

