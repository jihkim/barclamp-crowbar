# Copyright 2013, Dell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

############
# A 'deployment' of a barclamp represents a deployed (or deployable) cluster of roles 
#
# 'snapshots' is the history relation. It contains all historical deployments.
# snapshot (or head) is the currently active proposal snapshot (or queued or committing)
#

class Deployment < ActiveRecord::Base
  

  attr_accessible :name, :description, :barclamp_id, :snapshot_id

  validates_uniqueness_of   :name, :case_sensitive => false, :message => I18n.t("db.notunique", :default=>"Name item must be unique")
  validates_format_of       :name, :with=>/^[a-zA-Z][_a-zA-Z0-9]*$/, :message => I18n.t("db.lettersnumbers", :default=>"Name limited to [_a-zA-Z0-9]")
  
  has_many          :snapshots,           :inverse_of => :deployment, :dependent => :destroy
  has_one           :snapshot,            :class_name => "Snapshot", :primary_key => "snapshot_id", :foreign_key => 'id'
  alias_attribute   :head,                :snapshot

  belongs_to        :parent,              :class_name => "Deployment", :primary_key => "parent_id"

  scope             :system,              -> { where(:system=>true) }

  # active includes nothing being committed
  def active?
    head.active?
  end

  def committed?
    head.committed?
  end

  def proposed?
    head.proposed?
  end

  def state
    head.state
  end

  # Helper to atomically recommit a currently active or committed snapshot.
  def recommit(&block)
    raise "Can only be called on a system deployment" unless system?
    raise "Recommit must be passed a block that will take a snapshot!" unless block_given?
    Deployment.transaction do
      # if the head is committed (in transistion) then we can add it otherwise, we need to clone it
      new_c = (head.committed? ? head : head.deep_clone)
      block.call(new_c)
      new_c.save!
      # move the pointer (could be skipped if this was already head)
      self.snapshot_id = new_c.id 
      # reset all the node roles to ensure we re-evaluate
      new_c.node_roles.each { |nr| nr.commit! }
      self.save!
      return snapshot(true)
    end
  end

  # commit the current proposal (cannot be done if there is a committed proposal)
  def commit
    head.commit
  end
  
  # is this a system deployment?
  def system?
    read_attribute("system")
  end

  # available roles to be added to deployment
  def available_roles
    candidates = Role.active
    # except, don't include roles that we've already got
    in_use = head.roles
    candidates - in_use
  end

  # available nodes that could be used in the deployment
  def available_nodes
    candidates = Node.all
    # add some good logic here!
    candidates
  end

  # Lookup the roles available for the deployment, use the Proposal then Active 
  def roles
    head.roles
  end

end
