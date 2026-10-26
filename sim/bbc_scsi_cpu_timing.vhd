-- Master CPU plus the clock-enable/cycle-stretch equations from
-- bbc_micro_core.vhd and the CLKEN_COUNT increment from vidproc.vhd.
-- Explicit startup values make simulation deterministic; video/MOS are not
-- instantiated. Keep these equations aligned with their production sources.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bbc_scsi_cpu_timing is
    generic(INITIAL_PHASE : natural := 0);
    port(clock_48, reset_n : in std_logic;
         di : in unsigned(7 downto 0);
         addr : out unsigned(15 downto 0);
         dout : out unsigned(7 downto 0);
         rnw, cpu_enable, bus_enable, opcode_sync : out std_logic;
         regs : out std_logic_vector(63 downto 0));
end;

architecture sim of bbc_scsi_cpu_timing is
    signal div3 : unsigned(1 downto 0) := (others => '0');
    signal count : unsigned(3 downto 0) := to_unsigned(INITIAL_PHASE, 4);
    signal mask : unsigned(1 downto 0) := (others => '0');
    signal vid_en, cpu_en, bus_en : std_logic := '0';
    signal a : unsigned(15 downto 0);
    signal slow : std_logic;
begin
    addr <= a;
    cpu_enable <= cpu_en;
    bus_enable <= bus_en;
    slow <= '1' when a(15 downto 8) = x"FC" or a(15 downto 8) = x"FD" else '0';
    cpu : entity work.R65C02 port map (
        reset => reset_n, clk => clock_48, enable => cpu_en,
        nmi_n => '1', irq_n => '1', di => di, do => dout, addr => a,
        nwe => rnw, sync => opcode_sync, sync_irq => open, Regs => regs);

    process(clock_48)
    begin
        if rising_edge(clock_48) then
            if div3 = 2 then div3 <= (others => '0');
            else div3 <= div3 + 1; end if;
            if div3 = 1 then vid_en <= '1'; else vid_en <= '0'; end if;
            if vid_en = '1' then count <= count + 1; end if;
            if div3 = 1 and count(2 downto 0) = 7 then
                if slow = '1' and mask = 0 then
                    if count(3) = '0' then mask <= "01";
                    else mask <= "10"; end if;
                end if;
                if mask /= 0 then mask <= mask - 1; end if;
            end if;
            if div3 = 1 and count = 15 then bus_en <= '1';
            else bus_en <= '0'; end if;
            if div3 = 2 and count(2 downto 0) = 7 and mask = 0 then
                cpu_en <= '1'; else cpu_en <= '0'; end if;
        end if;
    end process;
end;
