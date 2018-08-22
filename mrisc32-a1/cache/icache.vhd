----------------------------------------------------------------------------------------------------
-- Copyright (c) 2018 Marcus Geelnard
--
-- This software is provided 'as-is', without any express or implied warranty. In no event will the
-- authors be held liable for any damages arising from the use of this software.
--
-- Permission is granted to anyone to use this software for any purpose, including commercial
-- applications, and to alter it and redistribute it freely, subject to the following restrictions:
--
--  1. The origin of this software must not be misrepresented; you must not claim that you wrote
--     the original software. If you use this software in a product, an acknowledgment in the
--     product documentation would be appreciated but is not required.
--
--  2. Altered source versions must be plainly marked as such, and must not be misrepresented as
--     being the original software.
--
--  3. This notice may not be removed or altered from any source distribution.
----------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common.all;

entity icache is
  port(
      -- Control.
      i_clk : in std_logic;
      i_rst : in std_logic;

      -- CPU interface.
      i_cpu_req : in std_logic;
      i_cpu_addr : in std_logic_vector(C_WORD_SIZE-1 downto 2);
      o_cpu_read_data : out std_logic_vector(C_WORD_SIZE-1 downto 0);
      o_cpu_read_data_ready : out std_logic;

      -- Memory interface.
      o_mem_req : out std_logic;
      o_mem_addr : out T_CACHE_LINE_ADDR;
      i_mem_read_addr : in T_CACHE_LINE_ADDR;
      i_mem_read_data : in T_CACHE_LINE_DATA;
      i_mem_read_data_ready : in std_logic
    );
end icache;

architecture rtl of icache is
  signal s_req_tag : T_CACHE_LINE_ADDR;
  signal s_req_offset : std_logic_vector(C_LOG2_CACHE_LINE_BYTES-1 downto 2);

  signal s_cache_hit : std_logic;
  signal s_mem_tag_matches_req_tag : std_logic;
  signal s_got_data_from_mem : std_logic;

  -- Instruction buffer.
  -- TODO(m): Replace this by a proper cache.
  signal s_next_buf_tag : T_CACHE_LINE_ADDR;
  signal s_next_buf_data : T_CACHE_LINE_DATA;
  signal s_next_buf_is_valid : std_logic;
  signal s_buf_tag : T_CACHE_LINE_ADDR;
  signal s_buf_data : T_CACHE_LINE_DATA;
  signal s_buf_is_valid : std_logic;
begin
  -- Decompose the word address into a cache tag and an offset.
  s_req_tag <= i_cpu_addr(C_WORD_SIZE-1 downto C_LOG2_CACHE_LINE_BYTES);
  s_req_offset <= i_cpu_addr(C_LOG2_CACHE_LINE_BYTES-1 downto 2);

  -- Check if we have a cache hit.
  s_cache_hit <= (i_cpu_req and s_buf_is_valid) when s_req_tag = s_buf_tag else '0';

  -- Did we get data from the memory that matches the current request?
  s_mem_tag_matches_req_tag <= '1' when i_mem_read_addr = s_req_tag else '0';
  s_got_data_from_mem <=
      i_cpu_req and
      i_mem_read_data_ready and
      s_mem_tag_matches_req_tag;

  -- Update the cache if necessary.
  s_next_buf_tag <= i_mem_read_addr when s_got_data_from_mem = '1' else s_buf_tag;
  s_next_buf_is_valid <= '1' when s_got_data_from_mem = '1' else s_buf_is_valid;

  BufWriteGen: for k in 0 to C_CACHE_LINE_WORDS-1 generate
  begin
    s_next_buf_data(k) <= i_mem_read_data(k) when s_got_data_from_mem = '1' else s_buf_data(k);
  end generate;

  -- Internal buffer registers (this is the "cache").
  process(i_rst, i_clk)
  begin
    if i_rst = '1' then
      s_buf_tag <= (others => '0');
      s_buf_is_valid <= '0';
    elsif rising_edge(i_clk) then
      s_buf_tag <= s_next_buf_tag;
      s_buf_data <= s_next_buf_data;
      s_buf_is_valid <= s_next_buf_is_valid;
    end if;
  end process;

  -- Send a request to the main memory if there was a miss.
  o_mem_req <= i_cpu_req and not s_cache_hit;
  o_mem_addr <= s_req_tag;

  -- Send the result if/when we have the data in the cache.
  o_cpu_read_data <= s_buf_data(to_integer(unsigned(s_req_offset)));
  o_cpu_read_data_ready <= s_cache_hit;
end rtl;
