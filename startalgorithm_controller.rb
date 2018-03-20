=begin
 * * Created on February 04, 2016 ( YES support for rectangular matrices)
 * ***************************************************************************************
 * This class enables a bipartite unbiased matching between N-Agents and N-Tasks.
 * The Agents select up to M-Tasks, with respect to their preferences and mark every
 * chosen Task by the priority order. The sequence of all preferences for all Agents make up cost-matrix.
 * The algorithm selects Tasks in order to maximize the cost matrix.
 * ****************************************************************************************
 * Author :  Kochkrov Furkat E.
 * Department of Mathematics and Computer Science
 * Saarland University, Saarbrucken,66123, Saarland, Germany.
 * s8fukoch@stud.uni-saarland.de 
 *****************************************************************************************
=end
class StartalgorithmController < ApplicationController
  unloadable

  def index

  	@rounds = PluginVotingRound.all
    @current_user=PluginUser.where(RedmineUserID: session[:user_id]).first
    #session[:current_plugin_user]=@current_user

    # @user_role = @current_user.Role       
    # if(@user_role == 1) #Админ    
      
    # else
    #   redirect_to "/redmine/polls/error"  
    # end  
      
     @max_vote = 5 #should be fetched from db
     @group_size_min = 4 
     @group_size_max = 7 
     @student_role = 2    
     #Votes and voters
     @round_id = params[:RoundID]
     @votes = PluginVote.where(RoundID: @round_id)
     @voters = @votes.group(:UserID) #.distinct()   
     #Groups and Team Leaders
     @groups = PluginGroup.where(RoundID: @round_id)
     @team_leaders = @groups.where(Leader: 1)
     #Topics of the current round
     @topics = PluginTopic.where(RoundID: @round_id)    
     @message = ""
     #GROUP_HUNGARIAN_ASSINGMENT = 1
     #GROUP_MAX_ASSINGMENT = 2
    # The number of topics should be greater or equal to number of groups so we can distribute groups by projects
    if @team_leaders.size > @topics.length
       @message = "The number of groups exceeds the total number of topics, topics cannot be distributed among groups.
                  For further proceedings, please add more topics"
      return
    end
     #Create a hash to store the results of algorithms => students distributed by projects   
     @resolver_result = Hash.new {|h,k| h[k] = Array.new } 

      users = Array.new(@team_leaders.size)
      (0..(users.size-1)).each do |s|
          users[s] = PluginUser.where(id:@team_leaders[s].UserID).first
      end 
      cost_matrix = hungarian_algorithm(users,@topics,false)
      #@res = cost_matrix
      mask = solve(cost_matrix)
      mask.each_with_index do |stud,s|
      stud.each_with_index do |topic,t|        
        if mask[s][t] == HungarianAlgorithmCore::STAR 
          user = PluginUser.where(id: cost_matrix[s][t].UserID).first 
            if not user.nil?  #@resolver_result[@topics[t]].size < @group_size_max and
              get_group_by_team_leader(user.id).each do |member|
                  @resolver_result[@topics[t]].push(PluginUser.where(id: member.UserID).first)      
              end
            end             
        end
      end
      end 
 

  #Single voting students
  single_users = Array.new
  @votes.group(:UserID).each do |voter|
    if @groups.where(UserID: voter.UserID).first.nil?       
      single_users.push(PluginUser.find(voter.UserID))
    end
  end   

  if single_users.size==0
    @message = "All students are already distributed among groups!"
    return
  end
   # @res = PluginUser.joins(" INNER JOIN plugin_votes 
   #    ON plugin_users.id = plugin_votes.UserID where plugin_votes.RoundID=#{@round_id} AND plugin_users.Role=2 
   #    GROUP BY plugin_users.id")

    #Assign single users 
    iter = 0
    students_assigned_by_groups = false
    #initialize hungarian algorithm, assign the cost matrix
    cost_matrix = hungarian_algorithm(single_users,@topics,false)    
    unassigned_users = Array.new

    while(iter < single_users.size / @topics.size) do #and not unassigned_users.size.zero?
      sub_cost_matrix = Array.new(@topics.size) { Array.new(@topics.size,0)}      
      sub_cost_matrix.each_with_index do |student,s_indx|
      next_user_indx = s_indx + iter * @topics.size

        user = single_users[next_user_indx]
        student.each_with_index do |topic, t|
          rank = cost_matrix[next_user_indx][t].Weight  
          sub_cost_matrix[s_indx][t] = PluginVote.new(:TopicID =>@topics[t].id,
                                                    :UserID  => user.nil?? nil : user.id,
                                                    :RoundID => @round_id,
                                                    :Weight => rank)
          unless user.nil?
            sub_cost_matrix[s_indx][t].UserID = user.id            
          end
        end
      end

      mask = solve(sub_cost_matrix)

      mask.each_with_index do |stud,s|
          stud.each_with_index do |topic,t|        
          if mask[s][t] == 1
            user = PluginUser.where(id: sub_cost_matrix[s][t].UserID).first
            unless user.nil?
              if @resolver_result[@topics[t]].size < @group_size_max
                 @resolver_result[@topics[t]].push(user) 
              else
                assigned = false
                @votes.where(UserID: user.id).order('Weight DESC').each do |vote|                  
                    @resolver_result.each do |topic,group|
                    if topic.id == vote.TopicID
                      if group.length <  @group_size_max
                        @resolver_result[topic].push(user)
                        assigned = true
                        break
                      end
                    end
                  end
                end # end votes
                if !assigned
                   @resolver_result.each do |topic,group|
                    max_deficit = 0
                    if group.length < @group_size_max and group.length >= @group_size_min
                       @resolver_result[topic].push(user)
                    end                 
                   end
                end #end assigned
              end             
            end #end unless         
          end
      end
     iter+=1
    end
      #Assign all students whose number is < group_min_size
      #@resolver_result = 
      groups_real = Hash.new {|h,k| h[k] = Array.new } 
      user_bank = Queue.new { |i|  } #Hash.new {|h,k| h[k] = Array.new } 
       @resolver_result.each do |topic,group|        
      #Check if the group has a group leader
        if group.length < @group_size_min 
          is_group = false
          group.each do |member|
            leader = PluginGroup.where(RoundID: params[:RoundID], Leader: 1, UserID: member.id)
            unless leader.nil?
              is_group = true 
              break
            end
          end #end group          
          if is_group
             groups_real[topic].push(group)
          else
             group.each do |member|
               user_bank.push(PluginUser.find(member.UserID))
             end            
             @resolver_result[topic] = Array.new
          end
        end  #endif              
      end
      #Assign users to the groups < group_min 
       groups_real.each do  |top, grp|
           while(@resolver_result[top].length <= @group_size_min and user_bank.size>0 ) #
           user = user_bank.pop()
           @resolver_result[top].push(PluginUser.find(user.UserID))
           end   
       end  
      
  end #end of index!!!

  

  def assign_max_group()
    unassigned_groups = Array.new
    assigned_groups = Array.new
    @topics.each_with_index do |topic,t|
      #Find all groups that voted for this topic 
      votes_group_current_topic = Array.new
      @votes.where(TopicID: topic.id).order('Weight DESC').each do |vote_topic|
            unless @groups.where(UserID: vote_topic.UserID).first.nil?       
              votes_group_current_topic.push(vote_topic)  #The voter is a group leader
            end
          end
          votes_group_current_topic.each_with_index do |vote,v|
            user = PluginUser.where(id: vote.UserID).first
            if @resolver_result[topic].size==0 and not assigned_groups.include?(user) 
              get_group_by_team_leader(vote.UserID).each do |member|
                 @resolver_result[topic].push(PluginUser.where(id: member.UserID).first)      
              end                  
              assigned_groups.push(user)
            else
              unassigned_groups.push(user)
            end
          end
        end
        unassigned_groups.each do |group|
        @topics.each_with_index do |topic,t|
          if @resolver_result[topic].size==0 
            if t >= unassigned_groups.size
             get_group_by_team_leader(group.id).each do |member|
                 @resolver_result[topic].push(PluginUser.where(id: member.UserID).first)      
              end   
            end     
          end   
        end 
      end
    end    
  end

  def hungarian_algorithm(users,topics,is_group=false)
    #Generate a cost matrix
    cost_matrix = Array.new(users.size) { Array.new(topics.size,nil)}
    users.each_with_index do |user, s|
      votes = @votes.where(UserID: user.id)#is_group ? user.UserID :
      votes.each_with_index do |vote, v|
        cost_matrix[s][v] = vote
        cost_matrix[s][v].Weight = @max_vote - vote.Weight
      end
     end
    remained_users = users.size % topics.size
    unless remained_users.zero?
      supplement_users = topics.size - remained_users
      ai_vote = PluginVote.new(:TopicID =>nil, 
          :UserID => nil, 
          :RoundID => params[:RoundID],
          :Weight => @max_vote)
      #Create a quadratic matrix to feed with the hungarian core algorithm
      cost_matrix_square = Array.new(users.size + supplement_users) { Array.new(topics.size,ai_vote)}
      cost_matrix.each_with_index do |stud,s|
        stud.each_with_index do |topic,t|
          cost_matrix_square[s][t] = cost_matrix[s][t]; 
        end
      end       

      for i in 0..(supplement_users-1)  
         users.push(PluginUser.new())
      end
      #Save the matrix
     cost_matrix = cost_matrix_square 
     end     
    return cost_matrix
  end


  def solve(cost_matrix)
   weight_matrix = Array.new(cost_matrix.size) { Array.new(cost_matrix.size,0)}  
   cost_matrix.each_with_index do |user,s|
      user.each_with_index do |vote,v|
      weight_matrix[s][v] = cost_matrix[s][v].Weight      
    end
    end
    hg_core = HungarianAlgorithmCore.new(weight_matrix)
    solution  = hg_core.solve 
    return hg_core.get_mask    
  end

  def get_group_by_team_leader(team_leader_id) 
    group_id = PluginGroup.where(RoundID: params[:RoundID], Leader: 1, UserID:team_leader_id).select(:GroupID)
    return @groups.where(GroupID: group_id) 
  end

  def topics_voted_by_groups()    
   @group_voted_topics = Array.new
   @team_leaders.each do |t|
    vote = @votes.where(UserID: t.UserID).first
    unless @group_voted_topics.include?(vote)
     @group_voted_topics.push(@topics.where(id:vote.TopicID).first)
     end
   end
   return @group_voted_topics
  end


end

class HungarianAlgorithmCore
  EMPTY = 0
  STAR  = 1
  PRIME = 2
  
  def initialize(matrix = nil); setup(matrix) if matrix; end
    
  def solve(matrix = nil)
    setup(matrix) if matrix
    raise "You must provide a matrix to solve." unless @matrix
    
    method = :minimize_rows
    while method != :finished
      method = self.send(*method)
    end
    
    return assignment
  end
  def get_mask
    @mask
  end
  private 

  def minimize_rows 
    
    @matrix.map! do |row|
      min_value = row.min
      row.map { |element| element - min_value }
    end
    
    return :star_zeroes
  end
  
  def star_zeroes
     
    traverse_indices do |row, column|
      if @matrix[row][column].zero? && !location_covered?(row, column)
        @mask[row][column] = STAR
        cover_cell(row, column)
      end
    end
    reset_covered_hash
    
    return :mask_columns
  end
  
  def mask_columns
    # Cover each column containing a starred zero. If all columns are covered, the starred zeros describe a complete set of unique assignments.
    
    index_range.each do |index|
      @covered[:columns][index] = true if column_mask_values_for(index).any? { |value| value == STAR }
    end
    
    return @covered[:columns].all? ? :finished : :prime_zeroes
  end
  
  def prime_zeroes
    
    while (row, column = find_uncovered_zero) != [-1, -1]
      @mask[row][column] = PRIME
      
      if star_loc_in_row = row_mask_values_for(row).index(STAR)
        @covered[:rows][row] = true
        @covered[:columns][star_loc_in_row] = false
      else
        return :augment_path, row, column
      end
    end
    
    return :adjust_matrix
  end
  
  def augment_path(starting_row, starting_column) 
   
    path = [[starting_row, starting_column]]
    path.instance_eval do
      def previous_row;    self.last[0]; end
      def previous_column; self.last[1]; end
    end
    
    loop do
      if row_containing_star = column_mask_values_for(path.previous_column).index(STAR)
        path << [row_containing_star, path.previous_column]
      else
        break
      end
      
      col_containing_prime = row_mask_values_for(path.previous_row).index(PRIME)
      path << [path.previous_row, col_containing_prime]
    end
    
    update_elements_in(path)
    traverse_indices { |row, column| @mask[row][column] = EMPTY if @mask[row][column] == PRIME }
    reset_covered_hash
    
    return :mask_columns
  end
  
  def adjust_matrix
    # Add the smallest value to every element of each covered row, subtract it from every element of each uncovered column, and call prime_zeroes.
    
    smallest_value = nil
    traverse_indices do |row, column| 
      if !location_covered?(row, column) && (smallest_value.nil? || @matrix[row][column] < smallest_value)
        smallest_value = @matrix[row][column]
      end
    end
    
    indices_of_covered_rows.each { |index| @matrix[index].map! { |value| value + smallest_value } }

    covered_columns = indices_of_uncovered_columns
    index_range.each { |row| covered_columns.each { |column| @matrix[row][column] -= smallest_value } }
    
    return :prime_zeroes
  end
  
  # - - - - - H E L P E R   M E T H O D S - - - - -
  
  def setup(matrix)
    @matrix  = matrix
    @length  = @matrix.length
    @mask    = Array.new(@length) { Array.new(@length, EMPTY) }                               # 2D array of constants (listed above)
    @covered = { :rows => Array.new(@length, false), :columns => Array.new(@length, false) }  # Boolean arrays
  end
  
  def assignment
    index_range.inject([]) { |path, row_index| path << [row_index, @mask[row_index].index(STAR)] }
  end
  
  def update_elements_in(path)    
    path.each do |cell|
      @mask[cell[0]][cell[1]] = case @mask[cell[0]][cell[1]]
      when STAR  then EMPTY
      when PRIME then STAR
      end
    end
  end
  
  def find_uncovered_zero
    traverse_indices do |row, column|
      return [row, column] if @matrix[row][column].zero? && !location_covered?(row, column)
    end
    [-1, -1]
  end
  
  def cover_cell(row, column)
    @covered[:rows][row] = @covered[:columns][column] = true
  end
  
  def reset_covered_hash
    @covered.values.each { |cover| cover.fill(false) }
  end
  
  def location_covered?(row, column)
    @covered[:rows][row] || @covered[:columns][column]
  end
  
  def row_mask_values_for(row)
    index_range.map { |column| @mask[row][column] }
  end
  
  def column_mask_values_for(column)
    index_range.map { |row| @mask[row][column] }
  end
  
  def indices_of_covered_rows
    index_range.select { |index| @covered[:rows][index] }
  end
    
  def indices_of_uncovered_columns
    index_range.select { |index| !@covered[:columns][index] }
  end
  
  def traverse_indices(&block)
    index_range.each { |row| index_range.each { |column| yield row, column } }
  end
  
  def index_range; (0...@length); end
end
