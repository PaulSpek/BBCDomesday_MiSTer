library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity tb_keyboard_clock is end;
architecture test of tb_keyboard_clock is
 signal clk : std_logic := '0';
 signal nr, en, autoscan, kp, irq, brk : std_logic := '0';
 signal key : std_logic_vector(10 downto 0) := (others=>'0');
 signal col : std_logic_vector(3 downto 0) := (others=>'0');
 signal row : std_logic_vector(2 downto 0) := (others=>'0');
begin
 clk <= not clk after 10 ns;
 dut: entity work.misterkeyboard port map(clk,nr,en,key,autoscan,col,row,kp,irq,brk,x"00");
 process
 procedure tick is begin wait until rising_edge(clk); wait for 1 ns; end;
 procedure send(code: std_logic_vector(7 downto 0); down: std_logic) is
 begin
  wait until falling_edge(clk);
  key <= (not key(10)) & down & '0' & code;
  tick; tick;
 end;
 begin
  tick; tick; nr<='1'; tick;
  -- A occupies column 1, row 4 in the BBC keyboard matrix.
  col<=x"1"; row<="100"; tick; tick;
  send(x"1C",'1'); tick;
  assert kp='1' and irq='1' report "A press missing" severity failure;
  send(x"1C",'0'); tick;
  assert kp='0' and irq='0' report "A release missing" severity failure;
  send(x"1C",'1');
  autoscan<='1'; tick;
  assert kp='0' report "autoscan must suppress keypress" severity failure;
  -- Single 48 MHz enable pulses must advance every scan column.
  for n in 1 to 16 loop
   wait until falling_edge(clk); en<='1'; tick;
   wait until falling_edge(clk); en<='0'; tick;
   if n=16 then assert irq='1' report "scan did not return to A column" severity failure; end if;
  end loop;
  send(x"78",'1'); tick;
  assert brk='1' report "BREAK press missing" severity failure;
  send(x"78",'0'); tick;
  assert brk='0' report "BREAK release missing" severity failure;
  report "PASS tb_keyboard_clock: press/release, autoscan, single-cycle enables and BREAK";
  stop;
 end process;
end;
