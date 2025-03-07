import time
import pytest
from port_dpb import Port
from port_dpb import DPB

@pytest.mark.usefixtures('dpb_setup_fixture')
@pytest.mark.usefixtures('dvs_lag_manager')
class TestPortDPBLag(object):
    def check_syslog(self, dvs, marker, log, expected_cnt):
        (exitcode, num) = dvs.runcmd(['sh', '-c', "awk \'/%s/,ENDFILE {print;}\' /var/log/syslog | grep \"%s\" | wc -l" % (marker, log)])
        assert num.strip() >= str(expected_cnt)

    @pytest.mark.skip(reason="Failing. Under investigation")
    def test_dependency(self, dvs):
        lag = "0001"
        p = Port(dvs, "Ethernet0")
        p.sync_from_config_db()

        # 1. Create PortChannel0001.
        self.dvs_lag.create_port_channel(lag)

        # 2. Add Ethernet0 to PortChannel0001.
        self.dvs_lag.create_port_channel_member(lag, p.get_name())
        time.sleep(2)

        # 3. Add log marker to syslog
        marker = dvs.add_log_marker()

        # 4. Delete Ethernet0 from config DB.
        p.delete_from_config_db()
        time.sleep(2)

        # 5. Verify that we are waiting in portsorch for the port
        #    to be removed from LAG, by looking at the log
        self.check_syslog(dvs, marker, "Unable to remove port Ethernet0: ref count 1", 1)

        # 6. Also verify that port is still present in ASIC DB.
        assert(p.exists_in_asic_db() == True)

        # 7. Remove port from LAG
        self.dvs_lag.remove_port_channel_member(lag, p.get_name())

        # 8. Verify that port is removed from ASIC DB
        assert(p.not_exists_in_asic_db() == True)

        # 9. Re-create port Ethernet0 and verify that it is
        #    present in CONFIG, APPL, and ASIC DBs
        p.write_to_config_db()
        p.verify_config_db()
        p.verify_app_db()
        p.verify_asic_db()

        # 10. Remove PortChannel0001 and verify that its removed.
        self.dvs_lag.remove_port_channel(lag)        
        time.sleep(30)
        self.dvs_lag.get_and_verify_port_channel(0)


# Add Dummy always-pass test at end as workaroud
# for issue when Flaky fail on final test it invokes module tear-down before retrying
def test_nonflaky_dummy():
    pass
