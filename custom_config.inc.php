<?php

$tlCfg->default_language = 'en_GB';

$tlCfg->results['status_code'] = array(
    'failed'        => 'f',
    'blocked'       => 'b',
    'passed'        => 'p',
    'not_run'       => 'n',
    'not_available' => 'x',
    'unknown'       => 'u',
    'all'           => 'a',
    'passed_with_conditions' => 'c'
);

$tlCfg->results['status_label'] = array(
    'not_run'       => 'test_status_not_run',
    'passed'        => 'test_status_passed',
    'failed'        => 'test_status_failed',
    'blocked'       => 'test_status_blocked',
    'passed_with_conditions' => 'test_status_passed_with_conditions'
);

$tlCfg->results['status_label_for_exec_ui'] = array(
    'not_run'       => 'test_status_not_run',
    'passed'        => 'test_status_passed',
    'failed'        => 'test_status_failed',
    'blocked'       => 'test_status_blocked',
    'passed_with_conditions' => 'test_status_passed_with_conditions'
);

$tlCfg->results['default_status'] = 'not_run';

$tlCfg->results['charts']['status_colour'] = array(
    'not_run'       => '000000',
    'passed'        => '006400',
    'failed'        => 'B22222',
    'blocked'       => '00008B',
    'passed_with_conditions' => 'FF8C11'
);

$g_tpl['inc_exec_controls'] = 'inc_exec_controls.tpl';

$tlCfg->document_generator->company_name = 'Venko Networks';
$tlCfg->document_generator->company_logo = 'logovenko.png';
$tlCfg->document_generator->company_logo_height = '53';
