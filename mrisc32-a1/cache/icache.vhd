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
      -- (ignored)
      i_clk : in std_logic;
      i_rst : in std_logic;

      -- CPU interface.
      i_cpu_req : in std_logic;
      i_cpu_addr : in std_logic_vector(C_WORD_SIZE-1 downto 2);
      o_cpu_read_data : out std_logic_vector(C_WORD_SIZE-1 downto 0);
      o_cpu_read_data_ready : out std_logic;

      -- Memory interface.
      o_mem_req : out std_logic;
      o_mem_addr : out std_logic_vector(C_WORD_SIZE-1 downto 2);
      i_mem_read_data : in std_logic_vector(C_WORD_SIZE-1 downto 0);
      i_mem_read_data_ready : in std_logic
    );
end icache;

architecture rtl of icache is
  -- Currently we only support a cache line size of 4 bytes (32 bits).
  constant C_LOG2_LINE_SIZE : positive := 2;
  constant C_LINE_SIZE : positive := 2**C_LOG2_LINE_SIZE;

  -- Each entry is 32 bits wide.
  constant C_LOG2_BYTES_PER_ENTRY : positive := 2;
  constant C_BYTES_PER_ENTRY : positive := 2**C_LOG2_BYTES_PER_ENTRY;
  constant C_LOG2_NUM_ENTRIES : positive := 12;  -- 16 KB
  constant C_NUM_ENTRIES : positive := 2**C_LOG2_NUM_ENTRIES;

  constant C_TAG_ADDR_SIZE : positive := C_LOG2_NUM_ENTRIES +
                                         C_LOG2_BYTES_PER_ENTRY -
                                         C_LOG2_LINE_SIZE;
  constant C_TAG_SIZE : positive := C_WORD_SIZE - C_TAG_ADDR_SIZE;

  signal s_data_write_data : std_logic_vector(C_WORD_SIZE-1 downto 0);
  signal s_data_write_addr : std_logic_vector(C_LOG2_NUM_ENTRIES-1 downto 0);
  signal s_data_we : std_logic;
  signal s_data_read_addr : std_logic_vector(C_LOG2_NUM_ENTRIES-1 downto 0);
  signal s_data_read_data : std_logic_vector(C_WORD_SIZE-1 downto 0);

  signal s_tag_write_data : std_logic_vector(C_TAG_SIZE-1 downto 0);
  signal s_tag_write_addr : std_logic_vector(C_TAG_ADDR_SIZE-1 downto 0);
  signal s_tag_we : std_logic;
  signal s_tag_read_addr : std_logic_vector(C_TAG_ADDR_SIZE-1 downto 0);
  signal s_tag_read_data : std_logic_vector(C_TAG_SIZE-1 downto 0);
begin
  -- Prepare the input signals for the cache memories.
  s_data_read_addr <= i_cpu_addr(C_LOG2_NUM_ENTRIES+C_LOG2_BYTES_PER_ENTRY-1 downto C_LOG2_BYTES_PER_ENTRY);

  -- TODO(m): Implement the rest...
  s_data_write_data <= (others => '0');
  s_data_write_addr <= s_data_read_addr;
  s_data_we <= '0';

  s_tag_read_addr <= (others => '0');
  s_tag_write_data <= (others => '0');
  s_tag_write_addr <= s_tag_read_addr;
  s_tag_we <= '0';

  -- Instantiate the data memory.
  data_ram_1: entity work.ram_dual_port
    generic map (
      WIDTH => C_WORD_SIZE,
      ADDR_BITS => C_LOG2_NUM_ENTRIES
    )
    port map (
      i_clk => i_clk,
      i_write_data => s_data_write_data,
      i_write_addr => s_data_write_addr,
      i_we => s_data_we,
      i_read_addr => s_data_read_addr,
      o_read_data => s_data_read_data
    );

  -- Instantiate the tag memory.
  tag_ram_1: entity work.ram_dual_port
    generic map (
      WIDTH => C_TAG_SIZE,
      ADDR_BITS => C_TAG_ADDR_SIZE
    )
    port map (
      i_clk => i_clk,
      i_write_data => s_tag_write_data,
      i_write_addr => s_tag_write_addr,
      i_we => s_tag_we,
      i_read_addr => s_tag_read_addr,
      o_read_data => s_tag_read_data
    );

  -- We just forward all requests to the main memory interface.
  o_mem_req <= i_cpu_req;
  o_mem_addr <= i_cpu_addr;

  -- ...and send the result right back.
  o_cpu_read_data <= i_mem_read_data;
  o_cpu_read_data_ready <= i_mem_read_data_ready;
end rtl;
